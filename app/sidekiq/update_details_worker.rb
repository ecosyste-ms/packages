class UpdateDetailsWorker
  include Sidekiq::Worker

  sidekiq_options queue: 'default'

  def perform(package_id)
    package = Package.find_by_id(package_id)
    package.try(:update_details)
    package.try(:touch)
  end
end