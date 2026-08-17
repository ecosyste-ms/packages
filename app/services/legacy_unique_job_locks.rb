require "sidekiq/api"
require "set"

class LegacyUniqueJobLocks
  AUDIT_CURSOR_KEY = "packages:legacy_unique_job_locks:audit_cursor".freeze
  CLEANUP_CURSOR_KEY = "packages:legacy_unique_job_locks:cleanup_cursor".freeze
  PRIMARY_LOCK_PATTERN = "uniquejobs:#{'?' * 32}".freeze
  PRIMARY_LOCK_REGEX = /\Auniquejobs:[0-9a-f]{32}\z/.freeze
  AUDIT_SCAN_COUNT = 5_000
  DEFAULT_SCAN_COUNT = 1_000
  MAX_SCAN_COUNT = 10_000
  MAX_LIVE_JOBS = 10_000

  class TooManyLiveJobs < StandardError
  end

  def self.audit(
    redis: nil,
    digests: SidekiqUniqueJobs::Digests.new,
    expiring_digests: SidekiqUniqueJobs::ExpiringDigests.new
  )
    unless redis
      return Sidekiq.redis do |connection|
        audit(redis: connection, digests: digests, expiring_digests: expiring_digests)
      end
    end

    primary = redis.scan("MATCH", PRIMARY_LOCK_PATTERN, "COUNT", AUDIT_SCAN_COUNT).count
    indexed = digests.page(page_size: 1).first + expiring_digests.page(page_size: 1).first

    {
      primary: primary,
      indexed: indexed,
      unindexed_estimate: [primary - indexed, 0].max
    }
  end

  def self.live_digests(max_jobs: MAX_LIVE_JOBS)
    digests = Set.new
    jobs_seen = 0
    add_job = lambda do |job|
      jobs_seen += 1
      if jobs_seen > max_jobs
        raise TooManyLiveJobs, "Live job scan exceeded the limit of #{max_jobs}"
      end

      add_job_digest(digests, job)
    end

    Sidekiq::ScheduledSet.new.each { |job| add_job.call(job) }
    Sidekiq::RetrySet.new.each { |job| add_job.call(job) }
    Sidekiq::Queue.all.each do |queue|
      queue.each { |job| add_job.call(job) }
    end
    Sidekiq::WorkSet.new.each do |_process_id, _thread_id, work|
      add_job.call(work.job)
    end
    # Cover jobs that moved from active execution into the retry set during the scan.
    Sidekiq::RetrySet.new.each { |job| add_job.call(job) }

    digests
  end

  def self.add_job_digest(digests, job)
    digest = job.item["lock_digest"] || job.item["unique_digest"]
    digest = digest.delete_suffix(":RUN") if digest
    digests << digest if digest.present?
  end

  def initialize(redis: nil, live_digests: nil, deleter: SidekiqUniqueJobs::BatchDelete, apply: false, scan_count: DEFAULT_SCAN_COUNT)
    @redis = redis
    @provided_live_digests = live_digests
    @deleter = deleter
    @apply = apply
    @scan_count = [[scan_count.to_i, 1].max, MAX_SCAN_COUNT].min
  end

  def call
    return call_with_redis(@redis) if @redis

    batch = Sidekiq.redis { |redis| scan_batch(redis) }
    live_digests = live_digests_for(batch[:candidates])
    Sidekiq.redis { |redis| finish_batch(redis, batch, live_digests) }
  end

  def call_with_redis(redis)
    batch = scan_batch(redis)
    live_digests = live_digests_for(batch[:candidates])
    finish_batch(redis, batch, live_digests)
  end

  def scan_batch(redis)
    cursor_key = @apply ? CLEANUP_CURSOR_KEY : AUDIT_CURSOR_KEY
    cursor = redis.get(cursor_key).presence || "0"
    next_cursor, keys = redis.call(
      "SCAN",
      cursor,
      "MATCH",
      PRIMARY_LOCK_PATTERN,
      "COUNT",
      @scan_count
    )
    keys.select! { |key| PRIMARY_LOCK_REGEX.match?(key) }
    matched = keys.length
    keys = keys.first(@scan_count)

    {
      cursor_key: cursor_key,
      cursor: cursor,
      next_cursor: next_cursor.to_s,
      keys: keys,
      matched: matched,
      candidates: unindexed_permanent_keys(redis, keys)
    }
  end

  def finish_batch(redis, batch, live_digests)
    candidates = batch[:candidates].reject { |digest| live_digests.include?(digest) }
    deleted = @apply && candidates.any? ? @deleter.call(candidates, redis) : 0
    redis.set(batch[:cursor_key], batch[:next_cursor])
    overflow = [batch[:matched] - batch[:keys].length, 0].max

    {
      cursor: batch[:cursor],
      next_cursor: batch[:next_cursor],
      scanned: batch[:keys].length,
      matched: batch[:matched],
      overflow: overflow,
      complete: batch[:next_cursor] == "0" && overflow.zero?,
      candidates: candidates.length,
      deleted: deleted,
      sample: candidates.first(10)
    }
  end

  def live_digests_for(candidates)
    return Set.new if candidates.empty?
    return @provided_live_digests if @provided_live_digests

    self.class.live_digests
  end

  def unindexed_permanent_keys(redis, keys)
    statuses = redis.pipelined do |pipeline|
      keys.each do |digest|
        pipeline.pttl(digest)
        pipeline.zscore(SidekiqUniqueJobs::DIGESTS, digest)
        pipeline.zscore(SidekiqUniqueJobs::EXPIRING_DIGESTS, digest)
      end
    end

    keys.each_with_index.filter_map do |digest, index|
      ttl = statuses[index * 3]
      digest_index_score = statuses[(index * 3) + 1]
      expiring_index_score = statuses[(index * 3) + 2]
      indexed = digest_index_score.present? || expiring_index_score.present?
      digest if ttl == -1 && !indexed
    end
  end
end
