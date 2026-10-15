class MavenCentralPublishedAtWorker
  include Sidekiq::Worker
  include Sidekiq::Throttled::Job
  sidekiq_options queue: :versions, lock: :until_executed, lock_ttl: 1.day.to_i
  sidekiq_throttle threshold: { limit: 2, period: 1 }

  def perform(registry_id, name, number)
    registry = Registry.find_by_id(registry_id)
    version = registry&.packages&.find_by(name: name)&.versions&.find_by(number: number)
    return if version.nil? || version.read_attribute(:published_at).present?

    published_at = registry.ecosystem_instance.central_published_at(name, number)
    return unless published_at

    package = version.package
    package.with_lock do
      version.update!(published_at: published_at)
      package.set_first_release_published_at
      package.set_latest_release_published_at
      package.save!
    end
  end
end
