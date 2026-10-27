class UpdateDependentPackagesCountWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :dependent_counts, lock: :until_executing, lock_ttl: 1.day.to_i,
                  lock_args_method: :lock_args, retry: 3
  sidekiq_throttle concurrency: { limit: 1 }, requeue: { with: :enqueue }

  def self.enqueue(package_ids)
    set(wait: 10.minutes).perform_bulk(package_ids.uniq.map { |id| [id] })
  end

  def self.lock_args(args)
    args.first(1)
  end

  def perform(package_id, batched = false)
    recount = DependentPackageRecount.new
    if batched || recount.active_for?(package_id)
      case recount.perform(package_id)
      when :pending
        self.class.perform_async(package_id, true)
      when :busy
        self.class.set(wait: 1.minute).perform_async(package_id, true)
      end
    else
      Package.with_dependency_query_limits do
        Package.select(:id, :dependent_packages_count).find_by(id: package_id)&.update_dependent_packages_count
      end
    end
  rescue ActiveRecord::QueryCanceled, ActiveRecord::LockWaitTimeout => error
    Rails.logger.warn("Deferring dependent count for package #{package_id}: #{error.class}")
    self.class.set(wait: 1.minute).perform_async(package_id, true)
  end
end
