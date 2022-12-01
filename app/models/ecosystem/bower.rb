# frozen_string_literal: true
module Ecosystem
  class Bower < Base
    def install_command(package, version = nil)
      "bower install #{package.name}" + (version ? "##{version}" : "")
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
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

    def packages
      @packages ||= begin
        packages = {}
        data = get("https://registry.bower.io/packages")

        data.each do |hash|
          packages[hash['name'].downcase] = hash.slice('name', 'url')
        end

        packages
      rescue
        {}
      end
    end

    def check_status(package)
      pkg = packages[package.name.downcase]
      return "removed" if pkg.nil?
      response = Typhoeus.head(pkg['url'], followlocation: true)
      "removed" if [400, 404, 410].include?(response.response_code)
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      repo_json = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=#{CGI.escape(pkg_metadata[:repository_url])}")
      return [] if repo_json.blank?
      tags_json = get_json("https://repos.ecosyste.ms/api/v1/hosts/#{repo_json['host']['name']}/repositories/#{repo_json['full_name']}/tags")
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

    def fetch_package_metadata(name)
      packages[name.downcase]
    end

    def map_package_metadata(package)
      bower_json = load_bower_json(package) || package
      return if bower_json.nil?
      {
        name: package["name"],
        repository_url: repo_fallback(package["url"], nil),
        licenses: bower_json['license'],
        keywords_array: bower_json['keywords'],
        homepage: repo_fallback(nil, bower_json["homepage"]),
        description: description(bower_json["description"])
      }
    end

    def dependencies_metadata(name, version, package)
      return [] unless package[:repository_url]
      github_name_with_owner = GithubUrlParser.parse(package[:repository_url]) # TODO this could be any host
      return [] unless github_name_with_owner
      deps = get_json("https://raw.githubusercontent.com/#{github_name_with_owner}/#{version}/bower.json")
      return [] unless deps.present?
      map_dependencies(deps["dependencies"], "runtime") + map_dependencies(deps["devDependencies"], "development")
    rescue StandardError
      []
    end

    def description(string)
      return nil if string.nil?
      return '' unless string.to_s.force_encoding('UTF-8').valid_encoding?
      string
    end

    def load_bower_json(package)
      return package unless package && package['url']
      github_name_with_owner = GithubUrlParser.parse(package['url'])  # TODO this could be any host
      return package unless github_name_with_owner
      json = get_json("https://raw.githubusercontent.com/#{github_name_with_owner}/master/bower.json") rescue {}
      return {} unless json.present?
    end
  end
end
