class UpdateRegistryRankingsWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low, lock: :until_executed, lock_ttl: 1.hour.to_i

  def perform(registry_id)
    Registry.find_by_id(registry_id).try(:update_rankings)
  end
end
