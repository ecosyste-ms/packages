class Registry < ApplicationRecord
  validates_presence_of :name, :url, :ecosystem

  validates_uniqueness_of :name, :url

  has_many :packages
  has_many :versions, through: :packages

  def all_package_names
    ecosystem_instance.all_package_names
  end

  def recently_updated_package_names
    ecosystem_instance.recently_updated_package_names
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
      sync_package(name)
    end
  end

  def sync_packages_async(package_names)
    package_names.each do |name|
      sync_package_async(name)
    end
  end

  def sync_package(name)
    package_metadata = ecosystem_instance.package_metadata(name)
    versions_metadata = ecosystem_instance.versions_metadata(package_metadata)

    package = packages.find_or_initialize_by({ name: package_metadata[:name], ecosystem: ecosystem })
    if package.new_record?
      package.assign_attributes(package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties))
      package.save! if package.changed?
    else
      attrs = package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties)
      package.update(attrs)
    end

    versions_metadata.each do |version|
      package.versions.create(version) unless package.versions.find { |v| v.number == version[:number] }
    end

    package.versions.includes(:dependencies).each do |version|
      next if version.dependencies.any?

      deps = begin
              ecosystem_instance.dependencies_metadata(name, version.number, package_metadata)
             rescue StandardError
               []
             end
      next unless deps&.any? && version.dependencies.empty?

      deps.each do |dep|
        possible_names = ecosystem_instance.package_find_names(name).map(&:downcase)
        named_package_id = packages.ecosystem(ecosystem).where("lower(packages.name) in (?)", possible_names).first.try(:id)
        version.dependencies.create(dep.merge(package_id: named_package_id.try(:strip)))
      end
    end
    
    package.reload
    package.last_synced_at = Time.now
    package.save
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
