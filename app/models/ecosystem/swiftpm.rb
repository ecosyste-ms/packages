# frozen_string_literal: true
module Ecosystem
  class Swiftpm < Base

    def self.purl_type
      'swift'
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
      if package['name'].starts_with?('github.com')
        "https://swiftpackageindex.com/#{package['name'].gsub('github.com/', '')}"
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
    end

    def check_status_url(package)
      registry_url(package).presence || package['repository_url']
    end

    def documentation_url(package, version = nil)
      if package['name'].starts_with?('github.com')
        "https://swiftpackageindex.com/#{package['name'].gsub('github.com/', '')}#{ version ? "/"+version : '' }/documentation"
      else
        nil
      end
    end

    def recently_updated_package_names
      u = "https://github.com/SwiftPackageIndex/PackageList/commits/main.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.match(/^Add (\w)/) && t.match(/^Add (.+)/)[1] }.uniq.compact
    rescue
      []
    end

    def download_url(package, version = nil)
      if version.present?
        version.metadata["download_url"]
      else
        return nil if package.repository_url.blank?
        return nil unless package.repository_url.include?('/github.com/')
        full_name = package.repository_url.gsub('https://github.com/', '').gsub('.git', '')
        
        "https://codeload.github.com/#{full_name}/tar.gz/refs/heads/master"
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return [] unless pkg_metadata[:tags_url]
      tags_json = get_json(pkg_metadata[:tags_url])
      return [] if tags_json.blank?

      tags_json.map do |tag|
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
      []
    end

    def fetch_package_metadata_uncached(name)
      json = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://#{CGI.escape(name)}")
      return nil if json.nil?
      return nil if json['error'].present?
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
        namespace: package['owner']
      }
    end

    def dependencies_metadata(name, version, package)
      return [] unless package[:repository_url]
      github_name_with_owner = GithubUrlParser.parse(package[:repository_url]) # TODO this could be any host
      return [] unless github_name_with_owner
      deps = get_raw("https://raw.githubusercontent.com/#{github_name_with_owner}/#{version}/Package.resolved")
      return [] unless deps.present?
      result = Bibliothecary::Parsers::SwiftPM.parse_package_resolved(deps)
      dependencies = result.is_a?(Bibliothecary::ParserResult) ? result.dependencies : result
      dependencies.map do |dep|
        dep_hash = dep.is_a?(Bibliothecary::Dependency) ? dep.to_h : dep
        {
          package_name: dep_hash[:name],
          requirements: dep_hash[:requirement],
          kind: dep_hash[:type],
          ecosystem: 'swiftpm'
        }
      end
    rescue StandardError
      []
    end

    def description(string)
      return nil if string.nil?
      return '' unless string.to_s.force_encoding('UTF-8').valid_encoding?
      string
    end
  end
end
