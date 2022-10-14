class Package < ApplicationRecord
  validates_presence_of :registry_id, :name, :ecosystem
  validates_uniqueness_of :name, scope: :registry_id

  belongs_to :registry
  counter_culture :registry
  has_many :versions
  has_many :dependencies, -> { group 'package_name' }, through: :versions

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }
  scope :created_after, ->(created_at) { where('created_at > ?', created_at) }
  scope :updated_after, ->(updated_at) { where('updated_at > ?', updated_at) }
  scope :active, -> { where(status: nil) }
  scope :with_repository_url, -> { where("repository_url <> ''") }
  scope :with_homepage, -> { where("homepage <> ''") }
  scope :with_repository_or_homepage_url, -> { where("repository_url <> '' OR homepage <> ''") }
  scope :with_repo_metadata, -> { where('length(repo_metadata::text) > 2 ') }

  before_save  :update_details
  after_commit :update_repo_metadata_async, on: :create

  def self.sync_least_recent_async
    Package.active.order('last_synced_at asc nulls first').limit(5000).each(&:sync_async)
  end

  def self.check_statuses_async
    Package.active.order('last_synced_at asc nulls first').limit(1000).each(&:check_status_async)
  end

  def self.sync_download_counts_async
    return if Sidekiq::Queue.new('default').size > 10_000
    Package.active
            .where(downloads: nil)
            .where(ecosystem: ['cargo','hackage','hex','homebrew','npm','nuget','packagist','puppet','rubygems','pypi'])
            .limit(1000).each(&:sync_async)
  end

  def to_param
    name.gsub('.', '%2E')
  end

  def description
    read_attribute(:description).presence || repo_metadata['description']
  end

  def update_dependent_packages_count
    update_columns(dependent_packages_count: dependent_packages.count)
  end

  def dependent_version_ids
    Dependency.where(package_name: name).pluck('distinct(version_id)') - [version_ids]
  end

  def dependent_versions
    Version.where(id: dependent_version_ids)
  end

  def dependent_package_ids
    Dependency.where(package_name: name).joins(:version).pluck('distinct(versions.package_id)') - [id]
  end

  def dependent_packages
    Package.where(id: dependent_package_ids).where(registry_id: registry_id)
  end

  def install_command
    registry.ecosystem_instance.install_command(self)
  end

  def registry_url
    registry.ecosystem_instance.registry_url(self)
  end

  def documentation_url
    registry.ecosystem_instance.documentation_url(self)
  end

  def download_url
    registry.ecosystem_instance.download_url(self, latest_version)
  end

  def archive_basename
    return if download_url.blank?
    File.basename(download_url)
  end

  def update_details
    normalize_licenses
    set_latest_release_published_at
    set_latest_release_number
  end

  def latest_version
    versions.sort.first
  end

  def set_latest_release_published_at
    self.latest_release_published_at = (latest_version.try(:published_at).presence || updated_at)
  end

  def set_latest_release_number
    self.latest_release_number = latest_version.try(:number)
  end

  def normalize_licenses
    self.normalized_licenses =
      if licenses.blank?
        []
      elsif licenses.length > 150
        ["Other"]
      else
        spdx = spdx_license
        if spdx.empty?
          ["Other"]
        else
          spdx
        end
      end
  end

  def spdx_license
    licenses
      .downcase
      .sub(/^\(/, "")
      .sub(/\)$/, "")
      .split("or")
      .flat_map { |l| l.split("and") }
      .map { |l| manual_license_format(l) }
      .flat_map { |l| l.split(/[,\/]/) }
      .map(&Spdx.method(:find))
      .compact
      .map(&:id)
  end

  def manual_license_format(license)
    # fixes "Apache License, Version 2.0" being incorrectly split on the comma
    license
      .gsub("apache license, version", "apache license version")
      .gsub("apache software license, version", "apache software license version")
  end

  def sync
    result = registry.sync_package(name)
    check_status unless result
  end

  def sync_async
    UpdatePackageWorker.perform_async(id)
  end

  def update_versions
    package_metadata = registry.ecosystem_instance.package_metadata(name)
    return false unless package_metadata
    versions_metadata = registry.ecosystem_instance.versions_metadata(package_metadata)

    versions_metadata.each do |version|
      if version[:integrity].present?
        v = versions.find{|ver| ver.integrity == version[:integrity] }
      else
        v = versions.find{|ver| ver.number == version[:number] }
      end
      if v
        v.assign_attributes(version) 
        v.save(validate: false)
      else
        versions.create(version)
      end
    end
  end

  def update_versions_async
    UpdateVersionsWorker.perform_async(id)
  end

  def update_integrities_async
    return if versions.first.try(:download_url).blank?
    versions.find_each(&:update_integrity_async)
  end

  def check_status
    status = registry.ecosystem_instance.check_status(self)
    update_columns(status: status, last_synced_at: Time.now) if status.present?
  end

  def check_status_async
    CheckStatusWorker.perform_async(id)
  end

  def repository_or_homepage_url
    repository_url.presence || homepage
  end

  def self.update_repo_metadata_async
    Package.with_repository_or_homepage_url.order('repo_metadata_updated_at DESC nulls first').limit(400).each(&:update_repo_metadata_async)
  end

  def update_repo_metadata_async
    return if repository_or_homepage_url.blank?
    UpdateRepoMetadataWorker.perform_async(id)
  end

  def update_repo_metadata
    return if repository_or_homepage_url.blank?
    repo_metadata = fetch_repo_metadata
    if repo_metadata.present?
      tags = fetch_tags
      repo_metadata.merge!({'tags' => tags}) if tags
      update_columns(repo_metadata: repo_metadata)
    end
    update_columns(repo_metadata_updated_at: Time.now)
  end

  def fetch_repo_metadata
    return if repository_or_homepage_url.blank?

    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end
    
    response = conn.get('/api/v1/repositories/lookup', url: repository_or_homepage_url)
    return nil unless response.success?
    return response.body
  end

  def fetch_tags
    return if repository_or_homepage_url.blank?
    return if repo_metadata['host'].blank?

    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end

    response = conn.get("/api/v1/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}/tags")
    return nil unless response.success?
    return response.body
  end
end
