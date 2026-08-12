class UpdateDownloadCountsWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :low, lock: :until_executed, lock_expiration: 1.hour.to_i
  sidekiq_throttle_as :registry_host

  def perform(registry_id, top = false)
    Registry.find_by_id(registry_id).try(:update_download_counts, top: top, limit: top ? 2000 : 1000)
  end
end
