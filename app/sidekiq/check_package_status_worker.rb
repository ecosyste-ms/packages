class CheckPackageStatusWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options lock: :until_executed, lock_ttl: 1.day.to_i
  sidekiq_throttle_as :registry_host

  def perform(registry_id, package_id)
    Package.find_by_id(package_id).try(:check_status)
  end
end
