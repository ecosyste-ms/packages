class SyncPackageWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical, #lock: :until_executed

  def perform(registry_id, name)
    Registry.find_by_id(registry_id).try(:sync_package, name)
  end
end