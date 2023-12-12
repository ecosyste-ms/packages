class UpdateIntegrityWorker
  include Sidekiq::Worker

  def perform(version_id)
    Version.find_by_id(version_id).try(:update_integrity)
  end
end