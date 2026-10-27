require 'sidekiq/api'

class RelinkDependenciesWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :dependent_counts, lock: :until_executing, lock_ttl: 1.day.to_i
  sidekiq_throttle concurrency: { limit: 1 }, requeue: { with: :enqueue }

  PROGRESS_KEY = "dependent_package_counts:#{Rails.env}:relink_progress".freeze

  def perform
    capacity = ReconcileDependentPackageCountsWorker::MAX_QUEUED_JOBS - Sidekiq::Queue.new('dependent_counts').size
    if capacity <= 0
      self.class.set(wait: 1.minute).perform_async
      return
    end

    cursor, upper_id = REDIS.hmget(PROGRESS_KEY, 'last_dependency_id', 'upper_dependency_id')
    unless upper_id
      upper_id = Package.with_dependency_query_limits { Dependency.maximum(:id) || 0 }
      cursor = 0
      REDIS.hset(PROGRESS_KEY, 'last_dependency_id', cursor, 'upper_dependency_id', upper_id)
    end
    result = Dependency.relink_missing_batch(after_id: cursor.to_i, upper_id: upper_id.to_i, batch_size: [capacity, 1000].min)
    UpdateDependentPackagesCountWorker.perform_bulk(result[:package_ids].map { |id| [id] }) if result[:package_ids].any?
    if result[:complete]
      REDIS.unlink(PROGRESS_KEY)
      self.class.set(wait: 1.hour).perform_async
    else
      REDIS.hset(PROGRESS_KEY, 'last_dependency_id', result[:cursor])
      self.class.perform_async
    end
  rescue ActiveRecord::QueryCanceled, ActiveRecord::LockWaitTimeout => error
    Rails.logger.warn("Deferring dependency relinking: #{error.class}")
    self.class.set(wait: 1.minute).perform_async
  end
end
