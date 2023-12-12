class UpdateAdvisoriesWorker
  include Sidekiq::Worker

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_advisories)
  end
end