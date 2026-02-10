# frozen_string_literal: true

module Ecosystem
  class Openvsx < Base
    def sync_maintainers_inline?
      true
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
      "#{@registry_url}/extension/#{package.name}/#{version}"
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/api/#{package.name}/#{version}/file/#{package.name.tr("/",".")}-#{version}.vsix"
    end

    def check_status_url(package)
      "#{@registry_url}/api/#{package.name}"
    end

    def all_package_names
      per_page = 50
      offset = 0
      packages = []
      loop do
        r = get("#{@registry_url}/api/-/query?includeAllVersions=false&size=#{per_page}&offset=#{offset}")["extensions"]
        break if r.blank? || r == []

        packages += r
        offset += per_page
      end
      packages.map { |package| "#{package["namespace"]}/#{package["name"]}" }
    rescue
      []
    end

    def recently_updated_package_names
      json = get("#{@registry_url}/api/-/search?size=50&offset=0&sortOrder=desc&sortBy=timestamp&includeAllVersions=false")
      return [] if json.blank?
      json["extensions"].map { |c| "#{c["namespace"]}/#{c["name"]}" }.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      get("#{@registry_url}/api/#{name}")
    rescue URI::InvalidURIError => e
      Rails.logger.warn "Invalid package name for OpenVSX: #{name.inspect} - #{e.message}"
      nil
    end

    def map_package_metadata(package)
      return false unless package.present? && package["allVersions"].present?
      {
        name: "#{package["namespace"]}/#{package["name"]}",
        namespace: package["namespace"],
        homepage: package["homepage"],
        description: package["description"],
        keywords_array: Array.wrap(package["tags"].reject{ it.starts_with? '__'}),
        licenses: package["license"],
        repository_url: repo_fallback(package["repository"], package["homepage"]),
        versions: package["allVersions"],
        downloads: package["downloadCount"],
        downloads_period: 'total',
        metadata: {
          categories: package["categories"],
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].keys.reject{ it == "latest" || existing_version_numbers.include?(it) }.map do |version|
        details = get("#{@registry_url}/api/#{pkg_metadata[:name]}/#{version}")
        {
          number: version,
          published_at: DateTime.parse(details['timestamp']),
          status: (details['downloadable'] ? nil : 'yanked')
        }
      end.compact
    rescue
      []
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] unless pkg
      [
        {
          uuid: pkg.dig("publishedBy", "loginName"),
          login: pkg.dig("publishedBy", "loginName"),
          name: pkg.dig("publishedBy", "fullName"),
          url: pkg.dig("publishedBy", "homepage")
        }
      ]
    end

    def maintainer_url(maintainer)
      maintainer.url
    end
  end
end
