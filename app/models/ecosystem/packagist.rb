# frozen_string_literal: true

module Ecosystem
  class Packagist < Base

    def self.purl_type
      "composer"
    end

    def purl(package, version = nil)
      PackageURL.new(
        type: purl_type,
        namespace: package.name.split('/').first,
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode,'iso-8859-1')
      ).to_s
    end


    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}##{version}"
    end

    def install_command(package, version = nil)
      "composer require #{package.name}" + (version ? ":#{version}" : "")
    end

    def download_url(_package, version)
      return nil unless version.present?
      version.metadata["download_url"]
    end

    def all_package_names
      get("#{@registry_url}/packages/list.json")["packageNames"]
    rescue
      []
    end

    def recently_updated_package_names
      u = "#{@registry_url}/feeds/releases.rss"
      updated = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      u = "#{@registry_url}/feeds/packages.rss"
      new_packages = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      (updated.map { |t| t.split(" ").first } + new_packages).uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      get_json("https://packagist.org/packages/#{name}.json")['package']
      # get_json("https://repo.packagist.org/p2/#{name}.json")&.dig("packages", name).presence || get_json("https://repo.packagist.org/p2/#{name}~dev.json")&.dig("packages", name)
    rescue
      false
    end

    def check_status(package)
      url = check_status_url(package)
      response = Faraday.head(url)
      return "removed" if [302, 404].include?(response.status)

      json = get_json("https://repo.packagist.org/p2/#{package.name}~dev.json")
      return "abandoned" if json == "404 not found, no packages here"
      res = json&.dig("packages", package.name)
      return "abandoned" if res == []
    end

    def deprecation_info(name)
      is_deprecated = fetch_package_metadata(name).dig("abandoned") || ""

      {
        is_deprecated: is_deprecated != "",
        message: "",
      }
    end

    def map_package_metadata(pkg_metadata)
      return false unless pkg_metadata
      latest_version = pkg_metadata['versions'][pkg_metadata['versions'].keys.first]
      return false if latest_version.nil?

      {
        name: pkg_metadata["name"],
        description: pkg_metadata["description"].try(:delete, "\u0000"),
        homepage: latest_version["homepage"],
        keywords_array: Array.wrap(latest_version["keywords"]).reject(&:blank?),
        licenses: Array.wrap(latest_version["license"]).join(","),
        repository_url: repo_fallback(latest_version["source"]&.fetch("url"), latest_version["homepage"]),
        versions: pkg_metadata['versions'],
        downloads: pkg_metadata["downloads"]&.fetch("total"),
        downloads_period: 'total',
        namespace: pkg_metadata["name"].split("/").first,
        metadata: {
          "funding" => latest_version["funding"],
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      acceptable_versions(pkg_metadata[:versions]).map do |name, version|
        metadata = {}
        
        metadata[:download_url] = version['dist']['url'] if version['dist']
        
        php_version = extract_php_version(version)
        metadata[:php_version] = php_version if php_version.present?
        
        platform_requirements = extract_platform_requirements(version)
        metadata[:platform_requirements] = platform_requirements if platform_requirements.present?
        
        metadata[:autoload] = version["autoload"] if version["autoload"].present?
        metadata[:extra] = version["extra"] if version["extra"].present?
        metadata[:suggest] = version["suggest"] if version["suggest"].present?
        
        {
          number: version["version"],
          published_at: version["time"],
          metadata: metadata
        }
      end
    end

    def acceptable_versions(versions)
      versions.select do |_n, k|
        # See: https://getcomposer.org/doc/articles/versions.md#branches
        (k['version'] =~ /^dev-.*/i).nil? && (k['version'] =~ /\.x-dev$/i).nil?
      end
    end

    def dependencies_metadata(_name, version, package)
      vers = package[:versions][version]
      return [] if vers.nil?

      map_dependencies(vers.fetch("require", {}).reject { |k, _v| k == "php" }, "runtime") +
        map_dependencies(vers.fetch("require-dev", {}).reject { |k, _v| k == "php" }, "Development")
    end

    def maintainers_metadata(name)
      json = get_json("https://packagist.org/packages/#{name}.json")['package']
      json['maintainers'].map do |user|
        {
          uuid: user["name"],
          login: user["name"],
        }
      end
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "https://packagist.org/users/#{maintainer.login}"
    end

    private

    def extract_php_version(version)
      require_section = version["require"] || {}
      require_section["php"]
    end

    def extract_platform_requirements(version)
      require_section = version["require"] || {}
      platform_reqs = require_section.select do |package, _constraint|
        package.start_with?("ext-") || package.start_with?("lib-") || package == "php-64bit" || package == "php-zts"
      end
      
      platform_reqs.empty? ? nil : platform_reqs
    end
  end
end
