class UpdateDependentReposCountWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_dependent_repos_count)
  end
end