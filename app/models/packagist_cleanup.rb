class PackagistCleanup
  STATE_KEY = 'packagist_cleanup'.freeze
  BATCH_SIZE = 100
  MAX_FAILURES = 100

  def initialize(registry, run: 'all', dry_run: true, limit: 100, max_seconds: 600, pause: 1,
    from_id: 0, to_id: nil, name: nil, output: $stdout)
    raise ArgumentError, 'Expected a Packagist registry' unless registry.ecosystem.casecmp?('packagist')
    raise ArgumentError, 'Invalid run name' unless run.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
    raise ArgumentError, 'LIMIT must be positive' unless limit.positive?
    raise ArgumentError, 'MAX_SECONDS must be positive and finite' unless max_seconds.finite? && max_seconds.positive?
    raise ArgumentError, 'PAUSE must be nonnegative and finite' unless pause.finite? && pause >= 0
    raise ArgumentError, 'Invalid ID range' unless from_id >= 0 && (to_id.nil? || to_id >= from_id)
    raise ArgumentError, 'Invalid package NAME' if name && !name.match?(%r{\A[a-z0-9_.-]+/[a-z0-9_.-]+\z}i)
    @registry = registry
    @run = run
    @dry_run = dry_run
    @limit = limit
    @max_seconds = max_seconds
    @pause = [pause, registry.rate_limit.to_f.positive? ? 1.0 / registry.rate_limit : 0].max
    @scope = {'from_id' => from_id, 'to_id' => to_id, 'name' => name.presence&.downcase}
    @output = output
  end

  def run
    Registry.connection_pool.with_connection do |connection|
      key = connection.quote("packagist_cleanup:#{@registry.id}")
      acquired = connection.select_value("SELECT pg_try_advisory_lock(hashtextextended(#{key}, 0))")
      raise 'Another Packagist cleanup is running for this registry' unless acquired
      begin
        run_batches
      ensure
        connection.execute("SELECT pg_advisory_unlock(hashtextextended(#{key}, 0))")
      end
    end
  end

  def run_batches
    @registry.reload
    @state = @registry.metadata.to_h.dig(STATE_KEY, @run)&.deep_dup
    raise ArgumentError, 'Run scope differs from its checkpoint; choose another RUN' if @state && @state.fetch('scope') != @scope
    @state ||= {'scope' => @scope, 'started_at' => Time.current.iso8601,
      'max_id' => [@registry.packages.maximum(:id).to_i, @scope['to_id']].compact.min,
      'after_name' => nil, 'processed' => 0, 'platform_dependencies_removed' => 0, 'failures' => {}}
    unless @dry_run || @registry.metadata.to_h.dig(PackagistMalware::MALWARE_STATE_KEY, 'packages').is_a?(Hash)
      raise 'Run packages:sync_packagist_malware before applying the cleanup'
    end
    @attempted = 0
    @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    emit(event: 'start', scope: @scope, checkpoint: @state)

    @state.fetch('failures').values.each do |failure|
      break if budget_exhausted?
      process(failure.fetch('id'), failure.fetch('name'), retrying: true)
    end
    after_name = @state['after_name']
    loop do
      break if budget_exhausted? || @state.fetch('failures').size >= MAX_FAILURES
      batch = remaining(after_name).limit([BATCH_SIZE, @limit - @attempted].min).pluck(:id, :name)
      break if batch.empty?
      batch.each do |id, name|
        break if budget_exhausted? || @state.fetch('failures').size >= MAX_FAILURES
        process(id, name)
        after_name = name
      end
    end
    complete = !remaining(after_name).exists? && @state.fetch('failures').empty?
    summary = {event: 'summary', attempted: @attempted, processed: @state.fetch('processed'),
      after_name: after_name, max_id: @state.fetch('max_id'), failures: @state.fetch('failures'),
      platform_dependencies_removed: @state.fetch('platform_dependencies_removed'), complete: complete}
    emit(**summary)
    summary
  end

  def remaining(after_name)
    relation = @registry.packages.where(id: @scope.fetch('from_id')..@state.fetch('max_id'))
    relation = relation.where('lower(name) = ?', @scope['name']) if @scope['name']
    relation = relation.where('name > ?', after_name) if after_name
    relation.order(:name)
  end

  def budget_exhausted?
    @attempted >= @limit || Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started >= @max_seconds
  end

  def process(id, name, retrying: false)
    @attempted += 1
    result = @dry_run ? preview(id, name, retrying: retrying) : apply_package(id, name, retrying: retrying)
    emit(**result)
  ensure
    if !@dry_run && @pause.positive? && !budget_exhausted?
      remaining_seconds = @max_seconds - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started)
      sleep [@pause, remaining_seconds].min if remaining_seconds.positive?
    end
  end

  def preview(id, name, retrying:)
    package = @registry.packages.find_by(id: id)
    edges = package ? platform_dependencies(package).sum(&:size) : 0
    {event: 'preview', id: id, name: name, status: package&.status,
      stored_versions: package&.versions_count, platform_dependencies: edges, retrying: retrying}
  end

  def apply_package(id, name, retrying:)
    registry = Registry.find(@registry.id)
    package = registry.packages.find_by(id: id)
    before = package&.status
    if package
      metadata = registry.ecosystem_instance.package_metadata(package.name)
      missing_response = registry.ecosystem_instance.fetch_malware_response(package.name.downcase) unless metadata
    end
    next_state = nil
    result = Registry.transaction do
      removed = 0
      if package
        package = registry.sync_package(package.name, force: true, maintenance: true)
        raise 'Packagist sync did not return the existing package' unless package.is_a?(Package) && package.id == id
        registry.ecosystem_instance.sync_malware(package.name.downcase, response: missing_response) if missing_response
        removed = remove_platform_dependencies(package)
        package = registry.packages.find(id)
        package.update!(versions_count: package.versions.count)
        package.update_details
      end
      next_state = checkpoint(registry, id, name, retrying: retrying, removed: removed)
      {event: package ? 'applied' : 'missing', id: id, name: name, status_before: before,
        status_after: package&.status, versions: package&.versions_count, platform_dependencies_removed: removed}
    end
    @state = next_state
    result
  rescue StandardError => error
    @state = checkpoint(Registry.find(@registry.id), id, name, retrying: retrying, error: error)
    {event: 'failed', id: id, name: name, error: "#{error.class}: #{error.message}".truncate(500)}
  end

  def platform_dependencies(package)
    return enum_for(__method__, package) unless block_given?
    adapter = @registry.ecosystem_instance
    Dependency.where(version_id: package.versions.select(:id)).where('lower(ecosystem) = ?', 'packagist')
      .select(:id, :package_name, :package_id).find_in_batches(batch_size: 1_000) do |batch|
      yield batch.select { |dependency| adapter.platform_package?(dependency.package_name.to_s) }
    end
  end

  def remove_platform_dependencies(package)
    removed = 0
    platform_dependencies(package).each do |batch|
      next if batch.empty?
      removed += Dependency.where(id: batch.map(&:id)).delete_all
      Package.where(id: batch.map(&:package_id).compact.uniq).find_each do |target|
        target.update_dependent_packages_count
        target.update_top_dependent_packages
      end
    end
    removed
  end

  def checkpoint(registry, id, name, retrying:, removed: 0, error: nil)
    state = @state.deep_dup
    state['updated_at'] = Time.current.iso8601
    state['after_name'] = name unless retrying
    if error
      previous = state.fetch('failures')[id.to_s]
      state['failures'][id.to_s] = {'id' => id, 'name' => name, 'attempts' => previous.to_h.fetch('attempts', 0) + 1,
        'error' => "#{error.class}: #{error.message}".truncate(500)}
    else
      state['failures'].delete(id.to_s)
      state['processed'] += 1
      state['platform_dependencies_removed'] += removed
    end
    registry.with_lock do
      runs = registry.metadata.to_h.fetch(STATE_KEY, {}).merge(@run => state)
      registry.update!(metadata: registry.metadata.to_h.merge(STATE_KEY => runs))
    end
    state
  end

  def emit(**fields)
    @output.puts(fields.merge(registry_id: @registry.id, run: @run, dry_run: @dry_run, at: Time.current.iso8601).to_json)
  end
end
