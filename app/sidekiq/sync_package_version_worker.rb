class SyncPackageVersionWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low,
                  lock: :until_executed,
                  lock_expiration: 1.hour.to_i

  def perform(registry_id, name, version)
    registry = Registry.find_by_id(registry_id)
    return if registry.nil?

    package = registry.packages.find_by(name: name)
    return if package&.versions&.exists?(number: version)

    registry.sync_package(name, force: package.present?, version: version)
  end
end
