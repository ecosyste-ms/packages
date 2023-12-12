class SyncMaintainersWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: :low

  def perform(package_id)
    Package.find_by_id(package_id).try(:sync_maintainers)
  end
end