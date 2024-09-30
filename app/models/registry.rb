class Registry < ApplicationRecord
  validates_presence_of :name, :url, :ecosystem

  validates_uniqueness_of :name, :url

  has_many :packages
  has_many :versions
  has_many :maintainers

  scope :not_docker, -> { where.not(ecosystem: 'docker') }

  def self.find_by_name!(name)
    name = 'cocoapods.org' if name == 'cocoapod.org'
    Registry.find_by!(name: name)
  end

  def self.update_extra_counts
    all.each(&:update_extra_counts)
  end

  def self.sync_all_recently_updated_packages_async
    not_docker.each(&:sync_recently_updated_packages_async)
  end

  def self.sync_all_packages
    not_docker.each(&:sync_all_packages)
  end

  def self.sync_all_missing_packages_async
    not_docker.each(&:sync_missing_packages_async)
  end

  def sync_in_batches?
    ecosystem_instance.sync_in_batches?
  end
  
  def self.sync_in_batches
    Registry.all.select(&:sync_in_batches?)
  end

  def self.sync_in_batches_outdated
    Registry.sync_in_batches.each{|r| r.packages.active.outdated.limit(1000).each(&:sync)};nil
  end

  def to_param
    name
  end

  def to_s
    if version.present?
      "#{ecosystem} #{version}"
    else
      name
    end
  end

  def all_package_names
    ecosystem_instance.all_package_names
  end

  def recently_updated_package_names
    ecosystem_instance.recently_updated_package_names.first(100).to_a
  end

  def recently_updated_package_names_excluding_recently_synced
    puts name
    existing_packages = packages.where(name: recently_updated_package_names)
    missing_names = recently_updated_package_names - existing_packages.map(&:name) 
    existing_packages.where("last_synced_at < ?", 10.minutes.ago).pluck(:name) + missing_names
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
    sync_packages(recently_updated_package_names_excluding_recently_synced)
  end

  def sync_all_packages_async
    sync_packages_async(all_package_names)
  end

  def sync_missing_packages_async
    sync_packages_async(missing_package_names)
  end

  def sync_recently_updated_packages_async
    sync_packages_async(recently_updated_package_names_excluding_recently_synced)
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

  def sync_package(name, force: false)
    existing_package = packages.find_by_name(name)
    if !force && existing_package&.last_synced_at && existing_package.last_synced_at > 1.day.ago
      # if recently synced, schedule for syncing 1 day later
      delay = (existing_package.last_synced_at + 1.day) - Time.now
      SyncPackageWorker.perform_in(delay, id, name)
      return
    end

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

    package.assign_attributes(package_metadata.except(:name, :releases, :versions, :version, :dependencies, :properties, :page, :time, :download_stats, :tags_url))

    update_repo_metadata_after_save = package.changed?

    package.save!

    package.update_repo_metadata_async if update_repo_metadata_after_save

    new_versions = []
    existing_version_numbers = package.versions.pluck('number')

    versions_metadata = ecosystem_instance.versions_metadata(package_metadata, existing_version_numbers)

    versions_metadata.each do |version|
      new_versions << version.merge(package_id: package.id, registry_id: id, created_at: Time.now, updated_at: Time.now) unless existing_version_numbers.find { |v| v == version.with_indifferent_access[:number].to_s && version.with_indifferent_access[:status].nil? }
    end

    if new_versions.any?
      new_versions.uniq! { |v| v.with_indifferent_access[:number].to_s }

      new_versions.each_slice(100) do |s|
        Version.upsert_all(s, unique_by: [:package_id, :number])
      end
      
      all_deps = []
      all_versions = package.versions

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
      
      all_deps.flatten.each_slice(100) do |s|
        # TODO upsert dependencies instead
        Dependency.insert_all(s) 
      end
    end

    package.update(versions_count: package.versions.count, last_synced_at: Time.zone.now)
    package.update_details
    package.update_dependent_repos_count_async
    package.sync_maintainers_async if ecosystem_class.instance_methods(false).include? :maintainers_metadata

    package.check_status

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

  def purl(package, version = nil)
    ecosystem_instance.purl(package, version)
  rescue
    nil
  end
  
  def purl_type
    ecosystem_instance.purl_type
  end

  def top_percentage_for(package, field)
    return nil if package.send(field).nil?
    Rails.cache.fetch("top_percentage_for/#{id}/#{field}/#{package.send(field)}", expires_in: 1.day) do
      packages.active.where("#{field} > ?", package.send(field)).count.to_f / packages_count * 100
    end
  end

  def top_percentage_for_json(package, json_field)
    return nil if package.repo_metadata.nil? || package.repo_metadata[json_field].nil?
    Rails.cache.fetch("top_percentage_for_json/#{id}/#{json_field}/#{package.repo_metadata[json_field]}", expires_in: 1.day) do
      packages.active.where("(repo_metadata ->> '#{json_field}')::text::integer > ?", package.repo_metadata[json_field]).count.to_f / packages_count * 100
    end
  end

  def update_extra_counts
    self.namespaces_count = packages.where.not(namespace: nil).distinct.count(:namespace)
    self.metadata['funded_packages_count'] = fetch_funded_packages_count
    self.keywords_count = count_keywords
    self.versions_count = packages.sum(:versions_count)
    self.downloads = packages.where(status: nil).or(packages.where.not(status: ['removed', 'unpublished'])).sum(:downloads)
    self.dependent_repos_count = packages.where(status: nil).or(packages.where.not(status: ['removed', 'unpublished'])).sum(:dependent_repos_count)
    save
  end

  def fetch_funded_packages_count
    count = 0
    packages.active.with_funding.select('id').find_in_batches(batch_size: 1000) do |batch|
      count += batch.length
    end
    count
  end

  def funded_packages_count
    metadata['funded_packages_count'] || 0
  end

  def funded_packages_percentage
    return 0 if packages_count.zero?
    funded_packages_count.to_f / packages_count * 100
  end

  def maintainers_supported?
    ecosystem_class.instance_methods(false).include?(:maintainers_metadata)
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
      m.role = maintainer[:role]
      m.save if m.changed?
      maintainer_records << m
    end

    existing_maintainers = package.maintainers

    new_maintainers = maintainer_records - existing_maintainers
    new_maintainers.each do |maintainer|
      package.maintainerships.create(maintainer: maintainer, role: maintainer.role)
    end

    removed_maintainers = existing_maintainers - maintainer_records
    removed_maintainers.each do |maintainer|
      package.maintainerships.find { |rp| rp.maintainer == maintainer }.destroy
      maintainer.update_packages_count
      maintainer.update_total_downloads
    end
    package.update_maintainers_count
    package.maintainers.reload.each do |maintainer|
      maintainer.update_packages_count
      maintainer.update_total_downloads
    end

  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def maintainer_url(maintainer)
    ecosystem_instance.maintainer_url(maintainer)
  end

  def namespace_maintainers(namespace)
    # packages.where(namespace: namespace).map(&:maintainers).flatten.uniq
    Maintainer.joins(:packages).where(packages: { namespace: namespace, registry_id: id }).distinct
  end

  def namespaces
    packages.where.not(namespace: nil).group(:namespace).order('COUNT(id) desc').count.to_a.map(&:first)
  end

  def sync_missing_namespace_packages
    @existing_package_names = existing_package_names
    namespaces.each do |namespace|
      begin
        sleep 1
        names = ecosystem_instance.namespace_package_names(namespace)
        missing_names = names - @existing_package_names
        puts "Syncing #{missing_names.count} missing packages for #{namespace}"
        sync_packages_async(missing_names)
      rescue
        puts "Error syncing missing packages for #{namespace}"
      end
    end
  end 

  def keywords
    Rails.cache.fetch("registries_keywords/#{id}", expires_in: 1.week) do
      Package.connection.select_rows("SELECT keywords, COUNT(keywords) AS keywords_count FROM (SELECT id, registry_id, unnest(keywords) AS keywords FROM packages WHERE registry_id = #{id} AND status IS NULL) AS foo GROUP BY keywords ORDER BY keywords_count DESC, keywords ASC LIMIT 50000;")
    end
  end

  def count_keywords
    Package.connection.select_rows("SELECT COUNT(DISTINCT keywords) AS keywords_count FROM (SELECT id, registry_id, unnest(keywords) AS keywords FROM packages WHERE registry_id = #{id} AND status IS NULL) AS foo;").first.first.to_i
  end

  def icon_url
    "https://github.com/#{github}.png"
  end

  def outdated_packages_count
    Rails.cache.fetch("outdated_packages_count/#{id}", expires_in: 15.minutes) do
      packages.active.outdated.count
    end
  end

  def active_packages_count
    Rails.cache.fetch("active_packages_count/#{id}", expires_in: 15.minutes) do
      packages.active.count
    end
  end

  def outdated_percentage
    return 0 if active_packages_count.zero?
    outdated_packages_count.to_f / active_packages_count * 100
  end

  def least_recently_synced_package_id
    Rails.cache.fetch("least_recently_synced_package_id/#{id}", expires_in: 15.minutes) do
      packages.active.order('last_synced_at asc').first.id
    end
  end

  def least_recently_synced_package
    packages.find_by_id(least_recently_synced_package_id)
  end

  def one_percent_of_packages_count
    count = (active_packages_count * 0.01).ceil
    return 3000 if count > 3000
    return 100 if count < 100
    count
  end

  def sync_one_percent_of_packages
    packages.active.outdated.order('RANDOM()').limit(one_percent_of_packages_count).each(&:sync_async)
  end

  def self.sync_worst_one_percent
    Registry.not_docker.sort_by(&:outdated_percentage).last.sync_one_percent_of_packages
  end

  # underproduction

  def package_ids_sorted_by_usage
    @package_ids_sorted_by_usage ||= packages.production.order(dependent_repos_count: :asc).pluck(:id)
  end

  def package_ids_sorted_by_quality
    @package_ids_sorted_by_quality ||= packages.production.order(Arel.sql("(issue_metadata->>'avg_time_to_close_issue')::text::float desc")).pluck(:id)
  end

  def update_production_rankings
    packages.production.each_instance(&:update_production_ranks)
  end

  def downloads
    read_attribute(:downloads) || 0
  end

  def find_critical_packages
    # only calculate critical packages for registries with more than 4000 packages
    return if packages_count < 4_000 
  
    if downloads > 0 && ecosystem != 'hackage' # hackage download numbers are not reliable
  
      # remove all existing critical packages
      packages.critical.update_all(critical: false)
  
      target_downloads = (downloads * 0.8).round
  
      count = 0
      critical_packages = []
      packages.active.order('downloads desc nulls last').each_instance do |p| 
        count += p.downloads
        critical_packages << p
        break if count > target_downloads
      end
  
      critical_packages.map(&:id).in_groups_of(1000, false) do |group|
        Package.where(id: group).update_all(critical: true)
      end
  
    elsif dependent_repos_count > 0
  
      # remove all existing critical packages
      packages.critical.update_all(critical: false)
  
      target_dependent_repos_count = (dependent_repos_count * 0.8).round
  
      count = 0
      critical_packages = []
      packages.active.order('dependent_repos_count desc nulls last').each_instance do |p|
        count += p.dependent_repos_count
        critical_packages << p
        break if count > target_dependent_repos_count
      end
  
      critical_packages.map(&:id).in_groups_of(1000, false) do |group|
        Package.where(id: group).update_all(critical: true)
      end
    end
  end
end
