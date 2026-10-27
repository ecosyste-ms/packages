class DependentPackageRecount
  REDIS_KEY = "dependent_package_counts:#{Rails.env}:active_recount".freeze
  STATE_FIELDS = %w[package_id run_id last_dependency_id upper_dependency_id status].freeze
  BATCH_SIZE = 1000
  STATE_TTL = 4.hours.to_i

  START_SCRIPT = <<~LUA.freeze
    if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
    redis.call('HSET', KEYS[1], 'package_id', ARGV[1], 'run_id', ARGV[2],
      'last_dependency_id', '0', 'upper_dependency_id', ARGV[3], 'status', 'scanning')
    redis.call('EXPIRE', KEYS[1], ARGV[4])
    return 1
  LUA

  CHECKPOINT_SCRIPT = <<~LUA.freeze
    if redis.call('HGET', KEYS[1], 'run_id') ~= ARGV[1] then return 'restart' end
    if redis.call('HGET', KEYS[1], 'last_dependency_id') ~= ARGV[2] then return 'stale' end
    local fields = {'last_dependency_id', ARGV[3], 'status', ARGV[4]}
    for i = 6, #ARGV do
      fields[#fields + 1] = 'dependent:' .. ARGV[i]
      fields[#fields + 1] = '1'
    end
    redis.call('HSET', KEYS[1], unpack(fields))
    redis.call('EXPIRE', KEYS[1], ARGV[5])
    return 'saved'
  LUA

  RESULT_SCRIPT = <<~LUA.freeze
    if redis.call('HGET', KEYS[1], 'run_id') ~= ARGV[1] then return -1 end
    if redis.call('HGET', KEYS[1], 'status') ~= 'complete' then return -1 end
    return redis.call('HLEN', KEYS[1]) - 5
  LUA

  CLEANUP_SCRIPT = <<~LUA.freeze
    if redis.call('HGET', KEYS[1], 'run_id') ~= ARGV[1] then return 0 end
    return redis.call('UNLINK', KEYS[1])
  LUA

  def state
    STATE_FIELDS.zip(REDIS.hmget(REDIS_KEY, *STATE_FIELDS)).to_h
  end

  def active_for?(package_id)
    REDIS.hget(REDIS_KEY, 'package_id') == package_id.to_s
  end

  def perform(package_id)
    package_id = Integer(package_id)
    current = state
    return :busy if current['package_id'] && current['package_id'] != package_id.to_s

    if current['run_id'].nil?
      upper_id = Package.with_dependency_query_limits do
        (Dependency.where(package_id: package_id).order(id: :desc).pick(:id) || 0) if Package.exists?(package_id)
      end
      return :complete if upper_id.nil?
      REDIS.eval(START_SCRIPT, keys: [REDIS_KEY], argv: [package_id, SecureRandom.hex(12), upper_id, STATE_TTL])
      current = state
      return :busy unless current['package_id'] == package_id.to_s
    end

    unless current['status'] == 'complete'
      rows = read_batch(package_id, current)
      complete = rows.length < BATCH_SIZE || rows.last&.fetch('id').to_i == current['upper_dependency_id'].to_i
      cursor = complete ? current['upper_dependency_id'] : rows.last.fetch('id')
      dependent_ids = rows.filter_map { |row| row['dependent_package_id'] }.uniq
      result = checkpoint(current, cursor, complete, dependent_ids)
      return :pending unless result == 'saved' && complete
    end

    count = REDIS.eval(RESULT_SCRIPT, keys: [REDIS_KEY], argv: [current['run_id']])
    return :pending if count.negative?
    Package.with_dependency_query_limits do
      Package.where(id: package_id).where('dependent_packages_count IS DISTINCT FROM ?', count)
             .update_all(dependent_packages_count: count, updated_at: Time.current)
    end
    REDIS.eval(CLEANUP_SCRIPT, keys: [REDIS_KEY], argv: [current['run_id']])
    :complete
  end

  def read_batch(package_id, current)
    Package.with_dependency_query_limits do
      Package.connection.select_all(<<~SQL).to_a
        WITH page AS MATERIALIZED (
          SELECT id, version_id FROM dependencies
          WHERE package_id = #{Integer(package_id)}
            AND id > #{Integer(current.fetch('last_dependency_id'))}
            AND id <= #{Integer(current.fetch('upper_dependency_id'))}
          ORDER BY id LIMIT #{BATCH_SIZE}
        )
        SELECT page.id, source.id AS dependent_package_id FROM page
        LEFT JOIN versions ON versions.id = page.version_id
        LEFT JOIN packages source ON source.id = versions.package_id
        ORDER BY page.id
      SQL
    end
  end

  def checkpoint(current, cursor, complete, dependent_ids)
    REDIS.eval(CHECKPOINT_SCRIPT, keys: [REDIS_KEY], argv: [
      current.fetch('run_id'), current.fetch('last_dependency_id'), cursor,
      complete ? 'complete' : 'scanning', STATE_TTL, *dependent_ids
    ])
  end
end
