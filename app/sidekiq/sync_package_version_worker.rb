class SyncPackageVersionWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :low,
                  lock: :until_executed,
                  lock_ttl: 1.day.to_i
  sidekiq_throttle_as :registry_host

  def perform(registry_id, name, version)
    registry = Registry.find_by_id(registry_id)
    return if registry.nil?

    package = registry.packages.find_by(name: name)
    return if package&.versions&.exists?(number: version)

    registry.sync_package(name, force: package.present?, version: version)
  end
end
