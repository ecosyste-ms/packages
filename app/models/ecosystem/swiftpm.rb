# frozen_string_literal: true
module Ecosystem
  class Swiftpm < Base
    VERSION_TAG = /\Av?\d+\.\d+(?:\.\d+)?(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/

    def self.purl_type
      'swift'
    end

    def self.normalized_package_name(name)
      name.downcase if name.to_s.match?(%r{\Agithub\.com/[^/]+/[^/]+\z}i)
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: package.name.split('/')[0..1].join('/'),
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode, 'iso-8859-1', invalid: :replace, undef: :replace, replace: '')
      }
    end

    def all_package_names
      get_json("https://raw.githubusercontent.com/SwiftPackageIndex/PackageList/main/packages.json").map do |url|
        url.gsub(/^https?:\/\//, '').gsub(/\.git$/,'')
      end
    end

    def registry_url(package, version = nil)
      if full_name = github_repository_name("https://#{package['name']}")
        "https://swiftpackageindex.com/#{full_name}"
      else
        package['repository_url']
      end
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg['name'].present?

      # Fall back to a direct request if not cached
      url = check_status_url(package)
      response = Faraday.head(url)
      return "removed" if [400, 404, 410].include?(response.status)
    rescue URI::InvalidURIError, Faraday::Error
      nil
    end

    def check_status_url(package)
      registry_url(package).presence || package['repository_url']
    end

    def documentation_url(package, version = nil)
      if full_name = github_repository_name("https://#{package['name']}")
        "https://swiftpackageindex.com/#{full_name}#{"/#{version}" if version}/documentation"
      else
        nil
      end
    end

    def recently_updated_package_names
      added = get_xml("https://swiftpackageindex.com/packages.rss").css('item guid').map(&:text)
      released = get_xml("https://swiftpackageindex.com/releases.rss").css('item guid').map { |g| g.text.split('/')[0..1].join('/') }
      (added + released).uniq.compact.map { |name| "github.com/#{name}" }
    rescue
      []
    end

    def download_url(package, version = nil)
      if version.present?
        version.metadata["download_url"]
      else
        full_name = github_repository_name(package.repository_url)
        branch = package.metadata&.dig('default_branch').presence || package.repo_metadata&.dig('default_branch').presence
        return nil unless full_name && branch

        "https://codeload.github.com/#{full_name}/tar.gz/refs/heads/#{ERB::Util.url_encode(branch)}"
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      @tags_complete = false
      return [] unless pkg_metadata[:tags_url]
      body = get_raw_no_exception(pkg_metadata[:tags_url]+"?per_page=#{REPOS_TAGS_PER_PAGE}", headers: {'Accept' => 'application/json'})
      return [] unless body
      tags_json = Oj.load(body)
      return [] unless tags_json.is_a?(Array) && tags_json.all? { |tag| tag.is_a?(Hash) && tag['name'].is_a?(String) }
      @tags_complete = tags_json.size < REPOS_TAGS_PER_PAGE

      tags_json.filter_map do |tag|
        next unless tag['name'].match?(VERSION_TAG)

        {
          number: tag['name'],
          published_at: tag['published_at'],
          metadata: {
            sha: tag['sha'],
            download_url: tag['download_url']
          }
        }
      end
    rescue StandardError
      @tags_complete = false
      []
    end

    def update_existing_versions(package, versions_metadata)
      sync_tag_backed_versions(package, versions_metadata, complete: @tags_complete == true)
    end

    def fetch_package_metadata_uncached(name)
      json = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://#{CGI.escape(name)}")
      return nil unless json.is_a?(Hash) && json['full_name'].present?
      json.merge('name' => name, 'repository_url' => "https://#{name}")
    rescue
      nil
    end

    def map_package_metadata(package)
      return if package.nil?
      {
        name: package["name"],
        repository_url: package['repository_url'],
        licenses: package['license'],
        keywords_array: package['topics'],
        homepage: package["homepage"],
        description: description(package["description"]),
        tags_url: package["tags_url"],
        namespace: package['owner'],
        metadata: {
          'normalized_name' => self.class.normalized_package_name(package['name']),
          'default_branch' => package['default_branch'],
          'tuist_registry_identity' => tuist_registry_identity(package['repository_url'])
        }.compact
      }
    end

    def github_repository_name(url)
      uri = URI.parse(url.to_s)
      return unless uri.is_a?(URI::HTTPS) && uri.host&.casecmp?('github.com') && uri.userinfo.nil?
      path = uri.path.delete_prefix('/').delete_suffix('/').delete_suffix('.git')
      path if path.match?(%r{\A[A-Za-z0-9-]+/[A-Za-z0-9._-]+\z})
    rescue URI::InvalidURIError
      nil
    end

    def tuist_registry_identity(repository_url)
      full_name = github_repository_name(repository_url)
      return unless full_name
      owner, repository = full_name.split('/')
      "#{owner}.#{repository.tr('.', '_')}"
    end

    def dependencies_metadata(name, version, package)
      url = resolved_file_url(package[:repository_url], version)
      return [] unless url
      deps = get_raw_no_exception(url)
      return [] unless deps.present?
      result = Bibliothecary::Parsers::SwiftPM.parse_package_resolved(deps)
      dependencies = result.is_a?(Bibliothecary::ParserResult) ? result.dependencies : result
      dependencies.map do |dep|
        dep_hash = dep.is_a?(Bibliothecary::Dependency) ? dep.to_h : dep
        package_name = dep_hash[:name]
        normalized_name = self.class.normalized_package_name(package_name)
        if normalized_name && normalized_name != package_name
          exact_id = registry.packages.where(name: package_name).pick(:id)
          if exact_id.nil? || Package.dependency_package_id(registry.id, 'swiftpm', normalized_name) == exact_id
            package_name = normalized_name
          end
        end
        {
          package_name: package_name,
          requirements: dep_hash[:requirement],
          kind: dep_hash[:type],
          ecosystem: 'swiftpm'
        }
      end
    rescue StandardError
      []
    end

    def resolved_file_url(repository_url, version)
      uri = URI.parse(repository_url.to_s)
      return unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil?
      ref = ERB::Util.url_encode(version.to_s)

      if full_name = github_repository_name(repository_url)
        "https://raw.githubusercontent.com/#{full_name}/#{ref}/Package.resolved"
      elsif uri.host&.casecmp?('gitlab.com') && (full_name = GitlabUrlParser.parse(repository_url))
        "https://gitlab.com/api/v4/projects/#{ERB::Util.url_encode(full_name)}/repository/files/Package.resolved/raw?ref=#{ref}"
      elsif uri.host&.casecmp?('bitbucket.org') && (full_name = BitbucketUrlParser.parse(repository_url))
        "https://api.bitbucket.org/2.0/repositories/#{full_name}/src/#{ref}/Package.resolved"
      elsif full_name = ForgeUrlParser.parse(repository_url)
        base = ForgeUrlParser.parse_to_full_url(repository_url).delete_suffix("/#{full_name}")
        "#{base}/api/v1/repos/#{full_name}/raw/Package.resolved?ref=#{ref}"
      end
    rescue URI::InvalidURIError
      nil
    end

    def update_dependency_links(package)
      dependencies = Dependency.where(version_id: package.versions.select(:id), ecosystem: 'swiftpm', package_id: nil)
      linked_ids = dependencies.distinct.pluck(:package_name).filter_map do |name|
        id = Package.dependency_package_id(package.registry_id, 'swiftpm', name)
        next unless id
        dependencies.where(package_name: name).in_batches.update_all(package_id: id)
        id
      end
      Package.where(id: linked_ids.uniq + [package.id]).find_each(&:update_dependent_packages_details)
    end

    def description(string)
      return nil if string.nil?
      return '' unless string.to_s.force_encoding('UTF-8').valid_encoding?
      string
    end
  end
end
