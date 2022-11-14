class Package < ApplicationRecord
  validates_presence_of :registry_id, :name, :ecosystem
  validates_uniqueness_of :name, scope: :registry_id

  belongs_to :registry
  counter_culture :registry
  has_many :versions
  has_many :dependencies # dependents 

  has_many :maintainerships, dependent: :delete_all
  has_many :maintainers, through: :maintainerships

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }
  scope :created_after, ->(created_at) { where('created_at > ?', created_at) }
  scope :updated_after, ->(updated_at) { where('updated_at > ?', updated_at) }
  scope :active, -> { where(status: nil) }
  scope :with_repository_url, -> { where("repository_url <> ''") }
  scope :with_homepage, -> { where("homepage <> ''") }
  scope :with_repository_or_homepage_url, -> { where("repository_url <> '' OR homepage <> ''") }
  scope :with_repo_metadata, -> { where('length(repo_metadata::text) > 2') }
  scope :without_repo_metadata, -> { where('length(repo_metadata::text) = 2') }
  scope :with_rankings, -> { where('length(rankings::text) > 2') }

  scope :with_funding, -> { where("length(metadata ->> 'funding') > 2 OR length(repo_metadata -> 'metadata' ->> 'funding') > 2 OR repo_metadata -> 'owner_record' -> 'metadata' ->> 'has_sponsors_listing' = 'true'") }

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
            .where(ecosystem: ['cargo','hackage','hex','homebrew','julia','npm','nuget','packagist','puppet','rubygems','pypi'])
            .limit(1000).each(&:sync_async)
  end

  def to_param
    name
  end

  def description
    read_attribute(:description).presence || repo_metadata['description']
  end

  def update_dependent_package_ids
    Dependency.where(package_id: nil, ecosystem: registry.ecosystem, package_name: name).in_batches.update_all(package_id: id)
  end

  def update_dependent_packages_count
    update_columns(dependent_packages_count: Dependency.where(package_id: id).joins(version: :package).count('distinct(packages.id)'))
  end

  def dependent_package_ids
    Dependency.where(package_id: id).joins(version: :package).pluck('distinct(packages.id)')
  end

  def dependent_packages
    Package.where(id: dependent_package_ids)
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
    if result
      update_dependent_repos_count_async
    else
      check_status
    end
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
      owner = fetch_owner
      repo_metadata.merge!({'owner_record' => owner}) if owner
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
  rescue
    nil
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
  rescue
    nil
  end

  def fetch_owner
    return if repository_or_homepage_url.blank?
    return if repo_metadata['host'].blank?

    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end

    response = conn.get("/api/v1/hosts/#{repo_metadata['host']['name']}/owners/#{repo_metadata['owner']}")
    
    return nil unless response.success?
    return response.body
  rescue
    nil
  end

  def repos_url
    return if repo_metadata.blank?
    return if repo_metadata['host'].blank?
    "https://repos.ecosyste.ms/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name'].gsub('.', '%2E')}"
  end

  def update_dependent_repos_count_async
    UpdateDependentReposCountWorker.perform_async(id)
  end

  def fetch_dependent_repos_count
    conn = Faraday.new('https://repos.ecosyste.ms') do |f|
      f.request :json
      f.request :retry
      f.response :json
    end

    response = conn.get("/api/v1/usage/#{ecosystem}/#{to_param}?per_page=1")
    return nil unless response.success?
    return response.body
  rescue
    nil
  end

  def update_dependent_repos_count
    json = fetch_dependent_repos_count
    return if json.blank?

    update_columns(dependent_repos_count: json['dependents_count'])
    update_rankings
  end

  def load_rankings
    rankings = {
      downloads: registry.top_percentage_for(self, :downloads),
      dependent_repos_count: registry.top_percentage_for(self, :dependent_repos_count),
      dependent_packages_count: registry.top_percentage_for(self, :dependent_packages_count),
      stargazers_count: registry.top_percentage_for_json(self, 'stargazers_count'),
      forks_count: registry.top_percentage_for_json(self, 'forks_count'),
    }
    if rankings.values.compact.any?
      rankings[:average] = rankings.values.compact.sum / rankings.values.compact.length.to_f
    else
      rankings[:average] = 100
    end
    rankings
  rescue 
    nil # handle database query error
  end

  def update_rankings
    new_rankings = load_rankings
    return if new_rankings.nil?
    update_column(:rankings, new_rankings) if rankings != new_rankings
  end

  def funding_links
    (package_funding_links + repo_funding_links + owner_funding_links).uniq
  end

  def package_funding_links
    return [] if metadata["funding"].blank?
    Array(metadata["funding"]).map{|f| f.is_a?(Hash) ? f['url'] : f }
  end

  def owner_funding_links
    return [] if repo_metadata.blank? || repo_metadata['owner_record'].blank? ||  repo_metadata['owner_record']["metadata"].blank?
    return [] unless repo_metadata['owner_record']["metadata"]['has_sponsors_listing']
    ["https://github.com/sponsors/#{repo_metadata['owner_record']['login']}"]
  end

  def repo_funding_links
    return [] if repo_metadata.blank? || repo_metadata['metadata'].blank? ||  repo_metadata['metadata']["funding"].blank?
    return [] if repo_metadata['metadata']["funding"].is_a?(String)
    repo_metadata['metadata']["funding"].map do |key,v|
      next if v.blank?
      case key
      when "github"
        Array(v).map{|username| "https://github.com/sponsors/#{username}" }
      when "tidelift"
        "https://tidelift.com/funding/github/#{v}"
      when "community_bridge"
        "https://funding.communitybridge.org/projects/#{v}"
      when "issuehunt"
        "https://issuehunt.io/r/#{v}"
      when "open_collective"
        "https://opencollective.com/#{v}"
      when "ko_fi"
        "https://ko-fi.com/#{v}"
      when "liberapay"
        "https://liberapay.com/#{v}"
      when "custom"
        v
      when "otechie"
        "https://otechie.com/#{v}"
      when "patreon"
        "https://patreon.com/#{v}"
      end
    end.flatten.compact
  end

  def sync_maintainers
    registry.sync_maintainers(self)
  end

  def sync_maintainers_async
    SyncMaintainersWorker.perform_async(id)
  end
end
