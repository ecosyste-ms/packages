class Package < ApplicationRecord
  include EcosystemsApiClient
  
  validates_presence_of :registry_id, :name, :ecosystem
  validates_uniqueness_of :name, scope: :registry_id

  belongs_to :registry
  counter_culture :registry
  has_many :versions
  has_many :dependencies # dependents 

  has_many :maintainerships, dependent: :delete_all
  has_many :maintainers, through: :maintainerships

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }
  scope :namespace, ->(namespace) { where(namespace: namespace) }
  scope :created_after, ->(created_at) { where('created_at > ?', created_at) }
  scope :updated_after, ->(updated_at) { where('updated_at > ?', updated_at) }
  scope :created_before, ->(created_at) { where('created_at < ?', created_at) }
  scope :updated_before, ->(updated_at) { where('updated_at < ?', updated_at) }
  scope :active, -> { where(status: nil) }
  scope :inactive, -> { where.not(status: nil) }
  scope :with_repository_url, -> { where("repository_url <> ''") }
  scope :without_repository_url, -> { where(repository_url: [nil, '']) }
  scope :with_homepage, -> { where("homepage <> ''") }
  scope :with_repository_or_homepage_url, -> { where("repository_url <> '' OR homepage <> ''") }
  scope :with_repo_metadata, -> { where('length(packages.repo_metadata::text) > 2') }
  scope :without_repo_metadata, -> { where('length(packages.repo_metadata::text) = 2') }
  scope :with_rankings, -> { where('length(rankings::text) > 2') }
  scope :without_rankings, -> { where('length(rankings::text) = 2') }
  scope :top, -> (percent = 1) { where("(rankings->>'average')::text::float < ?", percent) }
 
  scope :repository_url, ->(repository_url) { where("lower(repository_url) = ?", repository_url.try(:downcase)) }

  scope :outdated, -> { where('last_synced_at < ?', 1.month.ago) }

  scope :keyword, ->(keyword) { where("keywords @> ARRAY[?]::varchar[]", keyword) }
  scope :without_keywords, -> { where(keywords: '{}') }
  scope :with_keywords, -> { where.not(keywords: '{}') }

  scope :without_maintainerships, -> { includes(:maintainerships).where(maintainerships: {package_id: nil}) }

  scope :with_funding, -> { where("length(packages.metadata ->> 'funding') > 2 OR length(packages.repo_metadata -> 'metadata' ->> 'funding') > 2 OR repo_metadata -> 'owner_record' -> 'metadata' ->> 'has_sponsors_listing' = 'true'") }

  scope :with_issue_metadata, -> { where('length(issue_metadata::text) > 2') }
  scope :without_issue_metadata, -> { where(issue_metadata: nil) }
  scope :sole_maintainer, -> { where("json_array_length(issue_metadata->'maintainers') = 1") }

  scope :not_docker, -> { joins(:registry).where.not(registries: { ecosystem: 'docker' }) }

  scope :repository_owner, ->(owner) { where("repo_metadata->'owner_record'->>'login' = ?", owner) }

  after_create :update_rankings_async

  def self.find_by_normalized_name(name)
    normalized_name = name.downcase.gsub('_', '-').gsub('.', '-')
    pkg = where(name: name).limit(1).take
    pkg = where(name: normalized_name).limit(1).take if pkg.nil?
    # for pypi
    pkg = where("metadata->>'normalized_name' = ?", name.downcase.gsub('_', '-').gsub('.', '-')).limit(1).take if pkg.nil?
    pkg
  end

  def self.find_by_normalized_name!(name)
    project = find_by_normalized_name(name)
    raise ActiveRecord::RecordNotFound if project.nil?
    project
  end

  def self.keywords
    Package.connection.select_rows("SELECT keywords, COUNT(keywords) AS keywords_count FROM (SELECT id, unnest(keywords) AS keywords FROM packages WHERE status IS NULL) AS foo GROUP BY keywords ORDER BY keywords_count DESC, keywords ASC;").reject{|k,v| k.blank?}
  end

  def self.sync_least_recent_async
    Package.active.outdated.not_docker.order('RANDOM()').limit(4000).select('packages.id, packages.last_synced_at').each(&:sync_async)
  end

  def self.sync_least_recent_top_async
    Package.active.not_docker.order('RANDOM()').top(2).where('packages.last_synced_at < ?', 12.hours.ago).select('packages.id, packages.last_synced_at').limit(3_000).each(&:sync_async)
  end

  def self.check_statuses_async
    Package.not_docker.active.where('last_synced_at < ?', 5.weeks.ago).limit(1000).select('packages.id').each(&:check_status_async)
  end

  def self.sync_download_counts_async
    return if Sidekiq::Queue.new('default').size > 20_000
    Package.active.not_docker
            .where(downloads: nil)
            .where(ecosystem: ['cargo','clojars','docker','hackage','hex','homebrew','julia','npm','nuget','packagist','puppet','rubygems','pypi'])
            .limit(1000).select('packages.id').each(&:sync_async)
  end

  def self.sync_maintainers_async
    return if Sidekiq::Queue.new('default').size > 20_000
    Package.active.not_docker
            .without_maintainerships
            .where(ecosystem: ['cargo','clojars','cocoapods','cpan','cran','elpa','hackage','hex','npm','nuget','packagist','pypi','rubygems','racket','spack'])
            .order('last_synced_at desc nulls last')
            .limit(1000).select('packages.registry_id, packages.id').each(&:sync_maintainers_async)
  end

  def self.update_rankings_async
    return if Sidekiq::Queue.new('default').size > 20_000
    Package.active.without_rankings.order('last_synced_at desc nulls last').limit(1000).select('packages.id').each(&:update_rankings_async)
  end

  def to_param
    name
  end

  def description_with_fallback
    read_attribute(:description).presence || repo_metadata && repo_metadata['description']
  end

  def language
    return read_attribute(:language) || repo_metadata && repo_metadata['language']
  end

  def update_dependent_package_ids
    Dependency.where(package_id: nil, ecosystem: registry.ecosystem, package_name: name).in_batches.update_all(package_id: id)
  end

  def update_dependent_packages_count
    update(dependent_packages_count: Dependency.where(package_id: id).joins(version: :package).count('distinct(packages.id)'))
  end

  def update_dependent_packages_count_async
    UpdateDependentPackagesCountWorker.perform_async(id)
  end

  def update_dependent_packages_details
    update_dependent_package_ids
    update_dependent_packages_count
  end

  def update_maintainers_count
    update(maintainers_count: maintainerships.count)
  end

  def dependent_package_ids(kind: nil)
    scope = Dependency.where(package_id: id).joins(version: :package)
    scope = scope.where('dependencies.kind = ?', kind) if kind.present?
    scope.pluck('distinct(packages.id)')
  end

  def latest_dependent_package_ids(kind: nil)
    scope = Dependency.where(package_id: id).joins(version: :package).where('versions.latest = true')
    scope = scope.where('dependencies.kind = ?', kind) if kind.present?
    scope.pluck('distinct(packages.id)')
  end

  def dependent_packages(kind: nil)
    Package.where(id: dependent_package_ids(kind: kind))
  end

  def dependent_package_kinds
    Dependency.where(package_id: id).group(:kind).joins(version: :package).count('DISTINCT packages.id')
  end

  def latest_dependent_package_kinds
    Dependency.where(package_id: id).group(:kind).joins(version: :package).where('versions.latest = true').count('DISTINCT packages.id')
  end

  def latest_dependent_packages(kind: nil)
    Package.where(id: latest_dependent_package_ids(kind: kind))
  end

  def install_command
    registry.ecosystem_instance.install_command(self)
  end

  def registry_url
    registry.ecosystem_instance.registry_url(self)
  end

  def check_status_url
    registry.ecosystem_instance.check_status_url(self)
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

  def purl
    registry.purl(self)
  end

  def update_details
    set_latest_on_latest_version
    normalize_licenses
    set_latest_release_published_at
    set_latest_release_number
    set_first_release_published_at
    combine_keywords_and_topics
    save if changed?
  end

  def update_details_async
    UpdateDetailsWorker.perform_async(id)
  end

  def latest_version
    @latest_version ||= (latest_stable_version || versions.active.sort.first)
  end

  def latest_stable_version
    @latest_stable_version ||= versions.active.select(&:stable?).sort.first
  end

  def set_latest_release_published_at
    self.latest_release_published_at = (latest_version.try(:published_at).presence || updated_at)
  end

  def set_latest_release_number
    self.latest_release_number = latest_version.try(:number)
  end

  def set_latest_on_latest_version
    versions.update_all(latest: false)
    reload
    latest_version.update(latest: true) if latest_version
  end

  def first_version
    versions.sort.last
  end

  def set_first_release_published_at
    self.first_release_published_at = first_version.try(:published_at)
  end

  def combine_keywords_and_topics
    self.keywords = ((keywords_array||[]) + topics_array).uniq.compact.reject(&:blank?)
  end

  def topics_array
    return [] unless repo_metadata.present?
    repo_metadata['topics'] || []
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

  def licenses
    read_attribute(:licenses).presence || repo_metadata && repo_metadata['license']
  end

  def spdx_license
    licenses
      .downcase
      .sub(/^\(/, "")
      .sub(/\)$/, "")
      .split(" or ")
      .flat_map { |l| l.split(" and ") }
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
    return if last_synced_at && last_synced_at > 1.day.ago
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
      begin
        if v
          v.registry_id = registry_id
          v.assign_attributes(version) 
          v.save(validate: false)
        else        
          versions.create(version)
        end
      rescue ActiveRecord::RecordNotUnique
        Rails.logger.warn("Version not unique: #{version[:number]}")
      end
    end
    update_columns(versions_count: versions.count, versions_updated_at: Time.now)
  end

  def update_versions_async
    UpdateVersionsWorker.perform_async(id)
  end

  def update_integrities_async
    return if versions.first.try(:download_url).blank?
    versions.each_instance(&:update_integrity_async)
  end

  def check_status
    self.status = registry.ecosystem_instance.check_status(self)
    update(status: status, last_synced_at: Time.now) if status_changed? or status.present?
  end

  def check_status_async
    CheckStatusWorker.perform_async(id)
  end

  def repository_or_homepage_url
    repository_url.presence || homepage
  end

  def self.update_repo_metadata_async
    Package.with_repository_or_homepage_url.order('repo_metadata_updated_at DESC nulls first').limit(400).select('packages.id, packages.repository_url, packages.homepage').each(&:update_repo_metadata_async)
  end

  def update_repo_metadata_async
    return if repository_or_homepage_url.blank?
    UpdateRepoMetadataWorker.perform_async(id)
  end

  def update_repo_metadata
    if repository_or_homepage_url.blank?
      update(repo_metadata: nil)
      return
    end
    repo_metadata = fetch_repo_metadata
    if repo_metadata.present?
      tags = fetch_tags
      owner = fetch_owner
      repo_metadata.merge!({'owner_record' => owner}) if owner
      repo_metadata.merge!({'tags' => tags}) if tags
      update(repo_metadata: repo_metadata)
      ping_issues
      update_issue_metadata
    end
    update(repo_metadata_updated_at: Time.now)
  end

  def ping_repo
    return if repository_or_homepage_url.blank?
    if repo_metadata.blank?
      fetch_repo_metadata
    else
      connection = Faraday.new 'https://repos.ecosyste.ms' do |builder|
        builder.use Faraday::FollowRedirects::Middleware
        builder.request :retry, { max: 5, interval: 0.05, interval_randomness: 0.5, backoff_factor: 2 }
        builder.response :json
        builder.request :json
        builder.request :instrumentation
        builder.adapter Faraday.default_adapter, accept_encoding: "gzip"
      end
  
      response = connection.get("/api/v1/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}/ping")
    end
  rescue
    nil
  end

  def ping_usage
    ecosystems_api_get("https://repos.ecosyste.ms/api/v1/usage/#{ecosystem}/#{name}/ping")
  end

  def fetch_repo_metadata
    return if repository_or_homepage_url.blank?

    json = ecosystems_api_get('https://repos.ecosyste.ms/api/v1/repositories/lookup', params: { url: repository_or_homepage_url })
    
    if json.nil?
      # check for renamed repos
      resp = Faraday.head(repository_or_homepage_url)
      if resp.status == 301
        json = ecosystems_api_get('https://repos.ecosyste.ms/api/v1/repositories/lookup', params: { url: resp.headers['location'] })
      end
    end
    
    json || {}
  rescue
    {}
  end

  def fetch_tags
    return if repository_or_homepage_url.blank?
    return if repo_metadata['host'].blank?

    ecosystems_api_get("https://repos.ecosyste.ms/api/v1/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}/tags?per_page=1000") || []
  rescue
    []
  end

  def fetch_owner
    return if repository_or_homepage_url.blank?
    return if repo_metadata['host'].blank?

    ecosystems_api_get("https://repos.ecosyste.ms/api/v1/hosts/#{repo_metadata['host']['name']}/owners/#{repo_metadata['owner']}")
  rescue
    nil
  end

  def repos_url
    return if repo_metadata.blank?
    return if repo_metadata['host'].blank?
    "https://repos.ecosyste.ms/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name'].gsub('.', '%2E')}"
  end

  def repos_api_url
    return if repo_metadata.blank?
    return if repo_metadata['host'].blank?
    "https://repos.ecosyste.ms/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name'].gsub('.', '%2E')}"
  end

  def usage_url
    "https://repos.ecosyste.ms/usage/#{ecosystem}/#{to_param}"
  end

  def dependent_repositories_url
    "https://repos.ecosyste.ms/api/v1/usage/#{ecosystem}/#{to_param}/dependencies"
  end

  def update_dependent_repos_count_async
    UpdateDependentReposCountWorker.perform_async(id)
  end

  def fetch_dependent_repos(page = 1)
    ecosystems_api_get("https://repos.ecosyste.ms/api/v1/usage/#{ecosystem}/#{to_param}/dependencies?per_page=1000&page=#{page}")
  rescue
    nil
  end

  def fetch_dependent_repos_count
    ecosystems_api_get("https://repos.ecosyste.ms/api/v1/usage/#{ecosystem}/#{to_param}?per_page=1")
  rescue
    nil
  end

  def update_dependent_repos_count
    update_dependent_packages_details
    json = fetch_dependent_repos_count
    return if json.blank?
    return unless json.is_a?(Hash)

    update(dependent_repos_count: json['dependents_count'])
    update_rankings
  end

  def update_issue_metadata
    return if repo_metadata.blank?
    return if repo_metadata['host'].blank?

    issue_metadata = fetch_issue_metadata
    return if issue_metadata.blank?

    update(issue_metadata: issue_metadata)
  end

  def ping_issues
    return if repo_metadata.blank?
    return if repo_metadata['host'].blank?

    ecosystems_api_get("https://issues.ecosyste.ms/api/v1/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}/ping")
  end

  def fetch_issue_metadata
    return if repo_metadata.blank?
    
    json = ecosystems_api_get("https://issues.ecosyste.ms/api/v1/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}")
    return nil unless json
    
    json.except('full_name', 'host', 'owner','html_url', 'issue_authors', 'repository_url', 'issue_labels_count', 'pull_request_labels_count', 
      'issue_author_associations_count', 'pull_request_author_associations_count', 'pull_request_authors', 'past_year_issue_labels_count', 'past_year_pull_request_labels_count', 
      'past_year_issue_author_associations_count', 'past_year_pull_request_author_associations_count', 'past_year_issue_authors', 'past_year_pull_request_authors',
      'created_at', 'updated_at', 'status')
  rescue
    nil
  end

  def load_rankings
    rankings = {
      downloads: registry.top_percentage_for(self, :downloads),
      dependent_repos_count: registry.top_percentage_for(self, :dependent_repos_count),
      dependent_packages_count: registry.top_percentage_for(self, :dependent_packages_count),
      stargazers_count: registry.top_percentage_for_json(self, 'stargazers_count'),
      forks_count: registry.top_percentage_for_json(self, 'forks_count'),
      docker_downloads_count: registry.top_percentage_for(self, :docker_downloads_count)
    }
    if rankings.values.compact.any? && rankings.values.compact.any?{|v| v > 0 }
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
    update(rankings: new_rankings) if rankings != new_rankings
  end

  def update_rankings_async
    UpdateRankingsWorker.perform_async(id)
  end

  def funding_links
    (package_funding_links + repo_funding_links + owner_funding_links).uniq
  end

  def funding_domains
    funding_links.map{|l| URI.parse(l).host.sub(/^www\./, '') rescue nil }.uniq.compact
  end

  def package_funding_links
    return [] if metadata["funding"].blank?
    funding_array = metadata["funding"].is_a?(Array) ? metadata["funding"] : [metadata["funding"]] 
    funding_array.map{|f| f.is_a?(Hash) ? f['url'] : f }
  end

  def owner_funding_links
    return [] if repo_metadata.blank? || repo_metadata['owner_record'].blank? ||  repo_metadata['owner_record']["metadata"].blank?
    return [] unless repo_metadata['owner_record']["metadata"]['has_sponsors_listing']
    ["https://github.com/sponsors/#{repo_metadata['owner_record']['login']}"]
  rescue
    []
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
      when "polar"
        "https://polar.sh/#{v}"
      when 'buy_me_a_coffee'
        "https://buymeacoffee.com/#{v}"
      when 'thanks_dev'
        "https://thanks.dev/#{v}"
      else
        v
      end
    end.flatten.compact
  end

  def stars
    repo_metadata['stargazers_count'] if repo_metadata.present?
  end

  alias_method :stargazers_count, :stars

  def forks
    repo_metadata['forks_count'] if repo_metadata.present?
  end

  alias_method :forks_count, :forks

  def commit_stats
    repo_metadata['commit_stats'] if repo_metadata.present?
  end

  def commits_url
    return unless repo_metadata.present?
    "https://commits.ecosyste.ms/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}"
  end

  def commits_api_url
    return unless repo_metadata.present?
    "https://commits.ecosyste.ms/api/v1/hosts/#{repo_metadata['host']['name']}/repositories/#{repo_metadata['full_name']}"
  end

  def ping_commits
    return unless repo_metadata.present?
    ecosystems_api_get("#{commits_api_url}/ping")
  end

  def fetch_commit_stats
    return unless commits_api_url.present?
    ecosystems_api_get(commits_api_url)
  rescue
    nil
  end

  # Fetches commit stats from the commits service and stores in repo_metadata['commit_stats']
  # This provides an alternative to relying on the repos service to load commit data
  def update_commit_stats
    return unless repo_metadata.present?
    
    commit_stats = fetch_commit_stats
    if commit_stats.present?
      updated_metadata = repo_metadata.deep_dup
      updated_metadata['commit_stats'] = commit_stats
      update(repo_metadata: updated_metadata)
    end
  end

  def has_repository_stats?
    issue_metadata.present? || commit_stats.present? || repo_metadata&.dig('commit_stats').present?
  end

  def repository_committers_count
    safe_to_int(commit_stats&.dig('total_committers') || repo_metadata&.dig('commit_stats', 'total_committers'))
  end

  def repository_issue_authors_count
    safe_to_int(issue_metadata&.dig('past_year_issue_authors_count'))
  end

  def repository_pr_authors_count
    safe_to_int(issue_metadata&.dig('past_year_pull_request_authors_count'))
  end

  def repository_issues_count
    safe_to_int(issue_metadata&.dig('past_year_issues_count'))
  end

  def repository_prs_count
    safe_to_int(issue_metadata&.dig('past_year_pull_requests_count'))
  end

  def repository_maintainers_count
    issue_metadata&.dig('maintainers')&.length
  end

  def repository_active_maintainers_count
    issue_metadata&.dig('active_maintainers')&.length
  end

  def repository_dds_score
    dds_raw = issue_metadata&.dig('dds') || commit_stats&.dig('dds') || repo_metadata&.dig('commit_stats', 'dds')
    dds_raw.to_f if dds_raw.present?
  end

  def repository_host_name
    repo_metadata&.dig('host', 'name')
  end

  def safe_to_int(value)
    return nil if value.nil?
    return value if value.is_a?(Integer)
    return value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)
    nil
  end
  
  def sync_maintainers
    registry.sync_maintainers(self)
  end

  def sync_maintainers_async
    SyncMaintainersWorker.perform_async(id) if registry.maintainers_supported?
  end

  def related_packages
    return registry.packages.where('false') unless repository_url.present?
    registry.packages.repository_url(repository_url).where.not(id: id)
  end

  def fetch_advisories
    ecosystems_api_get("https://advisories.ecosyste.ms/api/v1/advisories?ecosystem=#{ecosystem}&package_name=#{to_param}") || []
  rescue
    []
  end

  def update_advisories
    advisories = fetch_advisories
    return if advisories.blank?
    update(advisories: advisories)
  end

  def update_advisories_async
    UpdateAdvisoriesWorker.perform_async(id)
  end

  def self.update_advisories
    advisories = ecosystems_api_get("https://advisories.ecosyste.ms/api/v1/advisories?updated_after=#{1.day.ago.iso8601}")
    return if advisories.nil?
    
    pkgs = advisories.map{|a| a['packages'].map{|p| [p['ecosystem'],p['package_name']]} }.uniq.flatten(1)
    pkgs.each do |ecosystem, package_name|
      Registry.where(ecosystem: ecosystem).each do |registry|
        registry.packages.find_by_name(package_name).try(:update_advisories_async)
      end
    end
  end

  def self.update_all_advisories
    packages = ecosystems_api_get("https://advisories.ecosyste.ms/api/v1/advisories/packages")
    return if packages.nil?
    
    packages.each do |h|
      Registry.where(ecosystem: h['ecosystem']).each do |registry|
        puts "#{registry.name} #{h['package_name']}"
        registry.packages.where(name: h['package_name']).each do |package|
          package.update_advisories
        end
      end
    end
  end

  def docker_usage_api_url
    "https://docker.ecosyste.ms/api/v1/usage/#{registry.ecosystem_instance.docker_usage_path(self)}"
  end

  def docker_usage_url
    "https://docker.ecosyste.ms/usage/#{registry.ecosystem_instance.docker_usage_path(self)}"
  end

  def fetch_docker_usage
    ecosystems_api_get(docker_usage_api_url)
  rescue
    nil
  end

  def update_docker_usage
    usage = fetch_docker_usage
    return if usage.blank?
    update(docker_dependents_count: usage['dependents_count'], docker_downloads_count: usage['downloads_count'])
  end

  def self.update_docker_usages
    ecosystems = ecosystems_api_get('https://docker.ecosyste.ms/api/v1/usage/')
    return if ecosystems.nil?
    
    ecosystems.each do |ecosystem|
      ecosystem_name = Ecosystem::Base.purl_type_to_ecosystem ecosystem['name']
      next if ecosystem_name.nil?
      puts "Updating #{ecosystem_name} docker usages"
      next_url = ecosystem['ecosystem_url']+'?per_page=1000'
      while next_url.present?
        puts next_url
        response = Faraday.get(next_url) do |req|
          req.headers['User-Agent'] = 'packages.ecosyste.ms'
        end
        next unless response.success?
        pkgs = JSON.parse response.body
        pkgs.each do |pkg|
          Registry.where(ecosystem: ecosystem_name).each do |registry|
            registry.packages.where(name: pkg['name']).each do |package|
              package.update(docker_dependents_count: pkg['dependents_count'], docker_downloads_count: pkg['downloads_count'])
            end
          end
        end
        
        next_url = response.headers['link'].split(',').find{|l| l.include?('rel="next"')}.try(:split, ';').try(:first).try(:gsub, /<|>/, '').try(:strip)
      end
    end
  rescue
    nil
  end

  def fetch_readme
    return if repo_metadata.blank?
    return if repo_metadata['metadata']['files']['readme'].blank?
    
    ecosystems_api_get('https://archives.ecosyste.ms/api/v1/archives/readme?url='+download_url)
  rescue
    nil
  end

  # underproduction

  def usage
    dependent_repos_count
  end

  def quality
    issue_metadata['avg_time_to_close_issue']
  end

  def update_production_ranks
    return unless usage.present? && quality.present?

    usage = calculate_usage_rank
    quality = calculate_quality_rank
    production = Math.log10(usage/quality.to_f)
    
    rankings['underproduction'] = {
      'usage_rank' => usage,
      'quality_rank' => quality,
      'production' => production
    }
    save
  end

  def calculate_usage_rank
    registry.package_ids_sorted_by_usage.index(id) + 1
  end

  def calculate_quality_rank
    registry.package_ids_sorted_by_quality.index(id) + 1
  end

  def outdated?
    last_synced_at && last_synced_at < 1.month.ago
  end

  scope :with_issue_close_time, -> { where.not(issue_metadata: nil).where.not("(issue_metadata->'avg_time_to_close_issue')::text = ?", 'null') }
  scope :production, -> { active.where('dependent_repos_count > 0').with_issue_close_time }

  # TODO some combination of quality factors that works for all projects in an ecosystem (even if repo unknown)
  # TODO some combination of usage factors that works for all projects in an ecosystem (i.e. avg ranking)

  scope :critical, -> { where(critical: true) }

  def self.funding_domains
    Rails.cache.fetch("funding:domains", expires_in: 1.week) do
      funding_domains = []
      Package.with_funding.active.find_each do |package| 
        funding_domains << package.funding_domains
      end
      
      funding_domains.flatten.group_by(&:itself).map{|k, v| [k, v.count]}.to_h.sort_by{|k, v| v}.reverse.to_h
    end
  end

  def self.critical_funding_domains
    funding_domains = []
    Package.critical.with_funding.active.find_each do |package| 
      funding_domains << package.funding_domains
    end
    
    funding_domains.flatten.group_by(&:itself).map{|k, v| [k, v.count]}.to_h.sort_by{|k, v| v}.reverse.to_h
  end

  def clean_up_duplicate_maintainerships
    maintainer_ids = maintainerships.group(:maintainer_id).count.select{|k,v| v > 1}.keys
    return if maintainer_ids.blank?
    maintainerships.where(maintainer_id: maintainer_ids).group(:maintainer_id).count.each do |maintainer_id, count|
      maintainerships.where(maintainer_id: maintainer_id).order('created_at desc').offset(1).destroy_all
    end
    update_maintainers_count
  end

  def scorecard_slug
    return unless repository_url.present?
    repository_url.gsub('https://', '').gsub('http://', '').gsub('www.', '')
  end

  def scorecard_api_url
    return unless scorecard_slug.present?
    "https://api.scorecard.dev/projects/#{scorecard_slug}"
  end

  def scorecard_url
    return unless scorecard_slug.present?
    "https://scorecard.dev/viewer/?uri=#{scorecard_slug}"
  end
end
