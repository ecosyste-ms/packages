class CheckStatusWorker
  include Sidekiq::Worker

  def perform(package_id)
    Package.find_by_id(package_id).try(:check_status)
  end
end