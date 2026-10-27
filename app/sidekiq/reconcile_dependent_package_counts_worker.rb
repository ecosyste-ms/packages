require 'sidekiq/api'

class ReconcileDependentPackageCountsWorker
  include Sidekiq::Worker
  sidekiq_options queue: :dependent_counts, lock: :until_executing, lock_ttl: 2.days.to_i

  CURSOR_KEY = "dependent_package_counts:#{Rails.env}:reconciliation:last_package_id".freeze
  MAX_QUEUED_JOBS = 1000

  def perform
    capacity = MAX_QUEUED_JOBS - Sidekiq::Queue.new('dependent_counts').size
    if capacity <= 0
      self.class.set(wait: 1.minute).perform_async
      return
    end

    after_id = REDIS.get(CURSOR_KEY).to_i
    ids = Package.with_dependency_query_limits do
      Package.where('id > ?', after_id).order(:id).limit(capacity).pluck(:id)
    end
    if ids.empty?
      REDIS.set(CURSOR_KEY, 0)
      self.class.set(wait: 1.day).perform_async
    else
      UpdateDependentPackagesCountWorker.perform_bulk(ids.map { |id| [id] })
      REDIS.set(CURSOR_KEY, ids.last)
      self.class.set(wait: 10.seconds).perform_async
    end
  end
end
