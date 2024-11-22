class UpdateIntegrityWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, lock_expiration: 2.hours.to_i

  def perform(version_id)
    Version.find_by_id(version_id).try(:update_integrity)
  end
end