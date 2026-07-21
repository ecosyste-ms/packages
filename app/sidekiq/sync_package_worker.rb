class SyncPackageWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical, lock: :until_executed, lock_expiration: 1.hour.to_i

  def perform(registry_id, name, force = false)
    registry = Registry.find_by_id(registry_id)
    return if registry.nil? || registry.sync_in_batches?

    force ? registry.sync_package(name, force: true) : registry.sync_package(name)
  end
end
