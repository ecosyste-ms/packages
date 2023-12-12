class UpdateVersionsWorker
  include Sidekiq::Worker

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_versions)
  end
end