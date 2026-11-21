class SyncPackagistChangeWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  # Each event must be accepted before discovery can advance its cursor.
  sidekiq_options queue: :critical
  sidekiq_throttle_as :registry_host

  def perform(registry_id, action)
    registry = Registry.find_by_id(registry_id)
    return unless registry&.ecosystem_instance.is_a?(Ecosystem::Packagist)

    registry.ecosystem_instance.sync_metadata_change(action)
  end
end
