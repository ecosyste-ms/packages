# frozen_string_literal: true

module Ecosystem
  class Nixpkgs < Base
    def self.purl_type
      'nix'
    end

    def sync_in_batches?
      true
    end

    def registry_url(package, _version = nil)
      "https://search.nixos.org/packages?channel=#{channel}&query=#{package.name}"
    end

    def install_command(package, _version = nil)
      "nix-env -iA nixpkgs.#{package.name}"
    end

    def documentation_url(package, _version = nil)
      position = package.metadata&.dig('position')
      return nil unless position.present?

      file_path, line = position.split(':')
      "https://github.com/NixOS/nixpkgs/blob/nixos-#{channel}/#{file_path}#L#{line}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return 'removed' if pkg.blank?
      nil
    end

    def channel
      @registry.version || 'unstable'
    end

    def packages_url
      "https://channels.nixos.org/nixos-#{channel}/packages.json.br"
    end

    def packages
      # Use class-level cache keyed by channel to avoid re-downloading
      # when new ecosystem instances are created (e.g., from package.registry)
      @@packages_cache ||= {}
      @@packages_cache[channel] ||= fetch_packages_json
    end

    def self.clear_packages_cache!
      @@packages_cache = {}
    end

    def fetch_packages_json
      Dir.mktmpdir do |dir|
        compressed_path = "#{dir}/packages.json.br"
        json_path = "#{dir}/packages.json"

        system("curl", "-sL", packages_url, "-o", compressed_path)
        system("brotli", "-d", compressed_path, "-o", json_path)

        data = Oj.load(File.read(json_path))
        data['packages'] || {}
      end
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      # nixpkgs doesn't have timestamps in packages.json
      # fall back to watching the GitHub repo commits
      url = "https://github.com/NixOS/nixpkgs/commits/nixos-#{channel}.atom"
      begin
        feed = SimpleRSS.parse(get_raw(url))
        # Extract package names from commit titles like "package-name: 1.0 -> 1.1"
        feed.items.flat_map do |item|
          title = item.title.to_s
          if title.include?(':')
            [title.split(':').first.strip]
          else
            []
          end
        end.uniq.first(100)
      rescue
        []
      end
    end

    def fetch_package_metadata(name)
      packages[name]
    end

    # Override to pass the attribute path (hash key) to map_package_metadata
    def package_metadata(name)
      pkg = fetch_package_metadata(name)
      map_package_metadata(pkg, name)
    end

    def map_package_metadata(pkg, attribute_path = nil)
      return false if pkg.blank? || pkg['pname'].blank?

      meta = pkg['meta'] || {}

      # Use the full nix attribute path (e.g. "python313Packages.numpy") as the name
      # since pname alone isn't unique in nixpkgs
      {
        name: attribute_path || pkg['pname'],
        description: meta['description'],
        homepage: meta['homepage'],
        licenses: map_licenses(meta['license']),
        repository_url: repo_fallback('', meta['homepage']),
        keywords_array: extract_keywords(pkg),
        metadata: {
          nix_attribute: pkg['name'],
          position: meta['position'],
          platforms: meta['platforms'],
          broken: meta['broken'],
          insecure: meta['insecure'],
          unfree: meta['unfree'],
          outputs: pkg['outputs']&.keys,
        }.compact
      }
    end

    def map_licenses(license_data)
      return nil if license_data.blank?

      case license_data
      when Hash
        license_data['spdxId'] || license_data['shortName']
      when Array
        license_data.map { |l| l.is_a?(Hash) ? (l['spdxId'] || l['shortName']) : l }.compact.join(', ')
      else
        license_data.to_s
      end
    end

    def extract_keywords(pkg)
      keywords = []
      meta = pkg['meta'] || {}

      # Add isBuildPythonPackage etc as keywords
      meta.each do |key, value|
        if key.start_with?('isBuild') && value.present?
          keywords << key.sub('isBuild', '').sub('Package', '').downcase
        end
      end

      keywords
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      pkg = fetch_package_metadata(pkg_metadata[:name])
      return [] if pkg.blank?

      meta = pkg['meta'] || {}

      [
        {
          number: pkg['version'],
          licenses: map_licenses(meta['license']),
          metadata: {
            nix_attribute: pkg['name'],
            system: pkg['system'],
            outputs: pkg['outputs']&.keys,
          }.compact
        }
      ]
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] if pkg.blank?

      maintainers = pkg.dig('meta', 'maintainers') || []
      maintainers.map do |m|
        next if m.blank?

        {
          uuid: m['github'] || m['email'] || m['name'],
          name: m['name'],
          email: m['email'],
          url: m['github'].present? ? "https://github.com/#{m['github']}" : nil,
        }.compact
      end.compact
    end

    def maintainer_url(maintainer)
      "https://github.com/#{maintainer.login}" if maintainer.login.present?
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: nil,
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
        qualifiers: { 'channel' => channel }
      }
    end
  end
end
