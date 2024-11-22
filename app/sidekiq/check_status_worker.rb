class CheckStatusWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, lock_expiration: 2.hours.to_i

  def perform(package_id)
    Package.find_by_id(package_id).try(:check_status)
  end
end