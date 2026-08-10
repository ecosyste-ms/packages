class SyncPackageVersionWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low,
                  lock: :until_executed,
                  lock_expiration: 1.hour.to_i,
                  lock_args_method: :lock_args

  def self.lock_args(args)
    args.first(2)
  end

  def perform(registry_id, name, version)
    registry = Registry.find_by_id(registry_id)
    return if registry.nil? || registry.packages.exists?(name: name)

    registry.sync_package(name, version: version)
  end
end
