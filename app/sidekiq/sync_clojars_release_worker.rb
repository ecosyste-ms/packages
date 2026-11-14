class SyncClojarsReleaseWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :critical
  sidekiq_throttle_as :registry_host

  def perform(registry_id, name)
    registry = Registry.find_by_id(registry_id)
    return unless registry&.ecosystem == 'clojars'

    registry.sync_package(name, force: true)
  end
end
