class Registry < ApplicationRecord
  validates_presence_of :name, :url, :ecosystem

  validates_uniqueness_of :name, :url

  has_many :packages
  has_many :versions, through: :packages

  def self.sync_all_recently_updated_packages_async
    all.each(&:sync_recently_updated_packages_async)
  end

  def versions_count
    packages.sum(:versions_count)
  end

  def all_package_names
    ecosystem_instance.all_package_names
  end

  def recently_updated_package_names
    ecosystem_instance.recently_updated_package_names.first(100)
  end

  def existing_package_names
    packages.pluck(:name)
  end

  def missing_package_names
    all_package_names - existing_package_names
  end

  def sync_all_packages
    sync_packages(all_package_names)
  end

  def sync_missing_packages
    sync_packages(missing_package_names)
  end

  def sync_recently_updated_packages
    sync_packages(recently_updated_package_names)
  end

  def sync_all_packages_async
    sync_packages_async(all_package_names)
  end

  def sync_missing_packages_async
    sync_packages_async(missing_package_names)
  end

  def sync_recently_updated_packages_async
    sync_packages_async(recently_updated_package_names)
  end

  def sync_packages(package_names)
    package_names.each do |name|
      begin
        sync_package(name)
      rescue => e
        puts "error syncing #{name} (#{ecosystem})"
        puts e.message
      end
    end
  end

  def sync_packages_async(package_names)
    SyncPackageWorker.perform_bulk(package_names.map{|name| [id, name]})
  end

  def sync_package(name)
    logger.info "Syncing #{name}"
    package_metadata = ecosystem_instance.package_metadata(name)
    return false unless package_metadata
    package_metadata[:ecosystem] = ecosystem
    versions_metadata = ecosystem_instance.versions_metadata(package_metadata)

    package = packages.find_or_initialize_by(name: package_metadata[:name])
    if package.new_record?
      package.assign_attributes(package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties, :page))
      package.save! if package.changed?
    else
      attrs = package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties, :page)
      package.update(attrs)
    end

    new_versions = []
    existing_version_numbers = package.versions.pluck('number')

    versions_metadata.each do |version|
      new_versions << version.merge(package_id: package.id, created_at: Time.now, updated_at: Time.now) unless existing_version_numbers.find { |v| v == version[:number] }
    end

    if new_versions.any?
      Version.insert_all(new_versions)
      
      all_deps = []
      all_versions = package.versions.includes(:dependencies)

      all_versions.each do |version|
        next if version.dependencies.any?

        deps = begin
                ecosystem_instance.dependencies_metadata(name, version.number, package_metadata)
              rescue StandardError
                []
              end
        next unless deps&.any? && version.dependencies.empty?

        all_deps << deps.map do |dep|
          dep.merge(version_id: version.id)
        end
      end
      
      Dependency.insert_all(all_deps.flatten) if all_deps.flatten.any?
    end

    updates = {last_synced_at: Time.zone.now}
    updates[:versions_count] = all_versions.length if all_versions

    package.update_columns(updates)
    return package
  end

  def sync_package_async(name)
    SyncPackageWorker.perform_async(id, name)
  end

  def ecosystem_instance
    @ecosystem_instance ||= ecosystem_class.new(url)
  end

  def ecosystem_class
    Ecosystem::Base.find(ecosystem)
  end
end
