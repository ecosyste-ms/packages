class UpdateRankingsWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: :low

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_rankings)
  end
end