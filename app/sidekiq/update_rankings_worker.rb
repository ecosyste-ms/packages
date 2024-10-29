class UpdateRankingsWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low, #lock: :until_executed

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_rankings)
  end
end