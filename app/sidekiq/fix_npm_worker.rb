class FixNpmWorker
  include Sidekiq::Worker
  sidekiq_options lock: :until_executed

  def perform(registry_id, name)
    r = Registry.find_by_id(registry_id)
    package = r.packages.find_by_name(name)
    return if package.nil?
    return if package.versions.reject{|v| v.read_attribute(:published_at).present?}.empty?
    metadata = r.ecosystem_instance.package_metadata(package.name)
    if metadata
      times = metadata[:time]
      if times
        package.versions.each do |version|
          if version.read_attribute(:published_at).present?
            puts "  #{version.number} (skipped)"
          return
          else
            puts "  #{version.number}"
            version.update_columns(published_at: times[version.number])
          end
        end
        package.save
      end
    end
  end
end