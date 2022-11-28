class Registry < ApplicationRecord
  validates_presence_of :name, :url, :ecosystem

  validates_uniqueness_of :name, :url

  has_many :packages
  has_many :versions, through: :packages
  has_many :maintainers

  def self.update_extra_counts
    all.each(&:update_extra_counts)
  end

  def self.sync_all_recently_updated_packages_async
    all.each(&:sync_recently_updated_packages_async)
  end

  def self.sync_all_packages
    all.each(&:sync_all_packages)
  end

  def self.sync_all_missing_packages_async
    all.each(&:sync_missing_packages_async)
  end

  def to_param
    name
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
    package_metadata[:ecosystem] = ecosystem.downcase

     # clean up incorrectly named package records
    if package_metadata[:name] != name 
      # example: request 'aracnid_utils' from pypi but get 'aracnid-utils' back
      packages.find_by_name(name).try(:destroy)
    end

    package = packages.find_or_initialize_by(name: package_metadata[:name])

    if package.new_record?
      package.assign_attributes(package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties, :page, :time, :download_stats, :tags_url))
      package.save! if package.changed?
    else
      attrs = package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties, :page, :time, :download_stats, :tags_url)
      package.update!(attrs)
    end

    new_versions = []
    existing_version_numbers = package.versions.pluck('number')

    versions_metadata = ecosystem_instance.versions_metadata(package_metadata, existing_version_numbers)

    versions_metadata.each do |version|
      new_versions << version.merge(package_id: package.id, created_at: Time.now, updated_at: Time.now) unless existing_version_numbers.find { |v| v == version[:number] }
    end

    if new_versions.any?
      new_versions.each_slice(100) do |s|
        Version.insert_all(s) 
      end
      
      all_deps = []
      all_versions = package.versions.includes(:dependencies)

      all_versions.each do |version|
         version
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
      
      all_deps.flatten.each_slice(100) do |s|
        Dependency.insert_all(s) 
      end
    end

    package.update(versions_count: package.versions.count, last_synced_at: Time.zone.now)
    package.update_details
    package.update_dependent_packages_count
    package.sync_maintainers_async

    # package.update_integrities_async
    return package
  end

  def sync_package_async(name)
    SyncPackageWorker.perform_async(id, name)
  end

  def ecosystem_instance
    @ecosystem_instance ||= ecosystem_class.new(self)
  end

  def ecosystem_class
    Ecosystem::Base.find(ecosystem)
  end

  def top_percentage_for(package, field)
    return nil if package.send(field).nil?
    Rails.cache.fetch("top_percentage_for/#{id}/#{field}/#{package.send(field)}", expires_in: 1.day) do
      packages.active.where("#{field} > ?", package.send(field)).count.to_f / packages_count * 100
    end
  end

  def top_percentage_for_json(package, json_field)
    return nil if package.repo_metadata[json_field].nil?
    Rails.cache.fetch("top_percentage_for_json/#{id}/#{json_field}/#{package.repo_metadata[json_field]}", expires_in: 1.day) do
      packages.active.where("(repo_metadata ->> '#{json_field}')::text::integer > ?", package.repo_metadata[json_field]).count.to_f / packages_count * 100
    end
  end

  def update_extra_counts
    self.namespaces_count = packages.where.not(namespace: nil).distinct.count(:namespace)
    self.metadata['funded_packages_count'] = fetch_funded_packages_count
    save
  end

  def fetch_funded_packages_count
    count = 0
    packages.active.with_funding.select('id').find_in_batches(batch_size: 1000) do |batch|
      count += batch.length
    end
    count
  end

  def funded_packages_percentage
    return 0 if packages_count.zero?
    metadata['funded_packages_count'].to_f / packages_count * 100
  end

  def sync_maintainers(package)
    
    maintainers_json = ecosystem_instance.maintainers_metadata(package.name)
    maintainer_records = []

    return unless maintainers_json.present?

    maintainers_json.each do |maintainer|
      m = maintainers.find_or_create_by(uuid: maintainer[:uuid])
      m.email = maintainer[:email]
      m.login = maintainer[:login]
      m.name = maintainer[:name]
      m.url = maintainer[:url]
      m.save if m.changed?
      maintainer_records << m
    end

    existing_maintainers = package.maintainers

    new_maintainers = maintainer_records - existing_maintainers
    new_maintainers.each do |maintainer|
      package.maintainerships.create(maintainer: maintainer)
    end

    removed_maintainers = existing_maintainers - maintainer_records
    removed_maintainers.each do |maintainer|
      package.maintainerships.find { |rp| rp.maintainer == maintainer }.destroy
      maintainer.update_packages_count
    end

    package.maintainers.reload.each(&:update_packages_count)
  end
end
