class SyncMaintainersWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low, lock: :until_executed, lock_expiration: 1.hour.to_i

  def perform(package_id)
    Package.find_by_id(package_id).try(:sync_maintainers)
  end
end