class SyncPackageWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: :critial

  def perform(registry_id, name)
    Registry.find_by_id(registry_id).try(:sync_package, name)
  end
end