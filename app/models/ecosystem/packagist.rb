# frozen_string_literal: true

module Ecosystem
  class Packagist < Base
    def sync_maintainers_inline?
      true
    end

    def self.purl_type
      "composer"
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: package.name.split('/').first,
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode,'iso-8859-1')
      }
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
      updated = feed_titles(u)
      u = "#{@registry_url}/feeds/packages.rss"
      new_packages = feed_titles(u)
      (updated.map { |t| t.split(" ").first } + new_packages).uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      package = begin
        fetch_package_enrichment(name)
      rescue StandardError => e
        Rails.logger.warn("Failed to fetch Packagist metadata for #{name}: #{e.message}")
        return false
      end
      package.merge('versions' => fetch_tagged_versions(package.fetch('name')))
    end

    def fetch_package_enrichment(name)
      Rails.cache.fetch(['packagist', 'enrichment', name], expires_in: 12.hours) do
        response = request("https://packagist.org/packages/#{name}.json")
        raise "Package metadata returned HTTP #{response.status}" unless response.success?
        data = JSON.parse(response.body).fetch('package')
        data.except('versions').merge('package_version' => data.fetch('versions').values.first)
      end
    end

    def fetch_tagged_versions(name)
      key = ['packagist', 'tagged_versions', name]
      cached = Rails.cache.read(key)
      headers = {}
      headers['If-Modified-Since'] = cached['last_modified'] if cached && cached['last_modified'].present?
      response = request("https://repo.packagist.org/p2/#{name}.json", headers: headers)
      if response.status == 304 && cached
        return expand_tagged_versions(cached.fetch('body'), name)
      end
      raise "Tagged metadata returned HTTP #{response.status}" unless response.success?

      versions = expand_tagged_versions(response.body, name)
      Rails.cache.write(key, {'body' => response.body, 'last_modified' => response.headers['last-modified']}, expires_in: 1.day)
      versions
    end

    def expand_tagged_versions(body, name)
      data = JSON.parse(body)
      minified = data['minified']
      raise "Unsupported metadata minification #{minified}" unless minified.nil? || minified == 'composer/2.0'
      entries = data.fetch('packages').fetch(name)
      raise 'Expected a tagged version list' unless entries.is_a?(Array)

      previous = {}
      entries.each_with_object({}) do |entry, versions|
        expanded = minified ? previous.dup : {}
        entry.each do |key, value|
          if minified && value == '__unset'
            expanded.delete(key)
          else
            expanded[key] = value
          end
        end
        number = expanded.fetch('version')
        raise 'Missing version number' if number.blank?
        versions[number] = expanded
        previous = expanded
      end
    end

    def check_status(package)
      json = begin
        fetch_package_enrichment(package.name)
      rescue StandardError
        false
      end

      if json.blank? || json == false
        url = check_status_url(package)
        response = Faraday.head(url)
        return "removed" if [302, 404].include?(response.status)
      end

      return "abandoned" if json.is_a?(Hash) && json["abandoned"].present?

      p2_json = get_json("https://repo.packagist.org/p2/#{package.name}~dev.json")
      return "abandoned" if p2_json == "404 not found, no packages here"
      res = p2_json&.dig("packages", package.name)
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
      latest_version = pkg_metadata['package_version'] || pkg_metadata['versions'].values.first
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
          integrity: (version['dist'] && version['dist']['shasum'].present?) ? "sha1-#{version['dist']['shasum']}" : nil,
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
      json = fetch_package_enrichment(name)
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
