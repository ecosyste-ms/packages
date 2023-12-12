class UpdateIntegrityWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed

  def perform(version_id)
    Version.find_by_id(version_id).try(:update_integrity)
  end
end