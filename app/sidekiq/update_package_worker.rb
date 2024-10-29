class UpdatePackageWorker
  include Sidekiq::Worker
  sidekiq_options queue: :critical#, lock: :until_executed

  def perform(package_id)
    Package.find_by_id(package_id).try(:sync)
  end
end