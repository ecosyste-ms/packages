# frozen_string_literal: true

module Ecosystem
  class Carthage < Base

    def check_status_url(package)
      package.repository_url
    end

    def fetch_package_metadata(name)
      json = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/#{CGI.escape(name)}")
      return nil if json.nil?
      return nil if json['error'].present?
      json.merge('name' => name, 'repository_url' => "https://github.com/#{name}")
    end

    def recently_updated_package_names
      json = get_json("https://repos.ecosyste.ms/api/v1/package_names/carthage")
      return [] if json.nil?
      return [] if json['error'].present?
      json.first(20)
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

    def all_package_names
      get_json("https://repos.ecosyste.ms/api/v1/package_names/carthage")
    rescue
      []
    end

    def map_package_metadata(package)
      return nil unless package
      {
        name: package['name'],
        description: package["description"],
        repository_url: package["repository_url"],
        licenses: package['license'],
        keywords_array: package['topics'],
        homepage: package["homepage"],
        tags_url: package["tags_url"],
        namespace: package["owner"],
      }
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

    def dependencies_metadata(name, version, package)
      return [] unless package[:repository_url]
      github_name_with_owner = GithubUrlParser.parse(package[:repository_url]) 
      return [] unless github_name_with_owner
      deps = get_raw_no_exception("https://raw.githubusercontent.com/#{github_name_with_owner}/#{version}/Cartfile")
      return [] unless deps.present?
      Bibliothecary::Parsers::Carthage.parse_cartfile(deps).map do |dep|
        {
          package_name: dep[:name],
          requirements: dep[:requirement].chomp.precense || '*',
          kind: dep[:type],
          ecosystem: 'carthage'
        }
      end
    rescue StandardError
      []
    end
  end
end
