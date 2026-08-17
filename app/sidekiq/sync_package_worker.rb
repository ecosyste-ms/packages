class SyncPackageWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :critical, lock: :until_executed, lock_ttl: 1.day.to_i
  sidekiq_throttle_as :registry_host

  def perform(registry_id, name, force = false)
    registry = Registry.find_by_id(registry_id)
    return if registry.nil? || registry.sync_in_batches?

    registry.sync_package(name, force: force)
  end
end
