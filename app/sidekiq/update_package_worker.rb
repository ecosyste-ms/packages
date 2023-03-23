class UpdatePackageWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed, queue: :critical

  def perform(package_id)
    Package.find_by_id(package_id).try(:sync)
  end
end