class SyncPackageWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical, lock: :until_executed, lock_expiration: 1.hour.to_i

  def perform(registry_id, name)
    registry = Registry.find_by_id(registry_id)
    return if registry.nil? || registry.sync_in_batches?
    registry.sync_package(name)
  end
end