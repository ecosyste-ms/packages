class UpdateRepoMetadataWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :low, lock: :until_executed, lock_ttl: 1.day.to_i
  sidekiq_throttle concurrency: { limit: 5 }, requeue: { with: :enqueue }

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_repo_metadata)
  end
end
