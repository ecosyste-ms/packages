class UpdateDetailsWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default'

  def perform(package_id)
    Package.find_by_id(package_id).try(:update_details)
  end
end