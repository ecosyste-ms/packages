# frozen_string_literal: true

module Ecosystem
  class Openvsx < Base
    def self.purl_type
      'vscode-extension'
    end

    def self.legacy_purl_types
      ['openvsx']
    end

    def sync_maintainers_inline?
      true
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: package.name.split('/').first,
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode,'iso-8859-1'),
        # The vscode-extension purl type defaults to the VS Code Marketplace,
        # so Open VSX always names its registry explicitly
        qualifiers: { 'repository_url' => @registry_url }
      }
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/extension/#{package.name}/#{version}"
    end

    def download_url(package, version)
      return nil unless version.present?
      return version.metadata['download_url'] if version.metadata&.dig('download_url').present?
      "#{@registry_url}/api/#{package.name}/#{version}/file/#{package.name.tr("/",".")}-#{version}.vsix"
    end

    def check_status(package)
      json = fetch_package_metadata(package.name)
      return nil if json.present? && json.is_a?(Hash) && json["name"].present?

      # Fall back to a direct request if not cached
      url = check_status_url(package)
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)
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
          status: (details['downloadable'] ? nil : 'yanked'),
          integrity: version_integrity(details.dig('files', 'sha256')),
          metadata: {
            download_url: details.dig('files', 'download'),
            signature_url: details.dig('files', 'signature'),
            public_key_url: details.dig('files', 'publicKey'),
            sha256_url: details.dig('files', 'sha256'),
            target_platform: details['targetPlatform'],
            published_by: details['publishedBy'],
            published_with_trusted_publishing: details['publishedWithTrustedPublishing']
          }.compact
        }
      end.compact
    rescue
      []
    end

    def version_integrity(url)
      return nil if url.blank?
      checksum = get_raw_no_exception(url).to_s.strip
      "sha256-#{checksum.downcase}" if checksum.match?(/\A[0-9a-fA-F]{64}\z/)
    rescue Faraday::Error
      nil
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
