class UpdateDownloadCountsWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :low, lock: :until_executed, lock_expiration: 1.hour.to_i
  sidekiq_throttle_as :registry_host

  CURSOR_LIMIT = 1000
  TOP_LIMIT = 10_000

  def perform(registry_id, top = false)
    Registry.find_by_id(registry_id).try(:update_download_counts, top: top, limit: top ? TOP_LIMIT : CURSOR_LIMIT)
  end
end
