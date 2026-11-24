class UpdateUpstreamRepositoryWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low, lock: :until_executed, lock_ttl: 1.hour.to_i

  def perform(package_id)
    package = Package.includes(:registry).find_by_id(package_id)
    return if package.nil?

    ecosystem = package.registry.ecosystem_instance
    ecosystem.update_upstream_repository(package) if ecosystem.respond_to?(:update_upstream_repository)
  end
end
