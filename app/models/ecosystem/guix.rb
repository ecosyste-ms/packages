# frozen_string_literal: true

module Ecosystem
  class Guix < Base
    def self.purl_type
      'guix'
    end

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def registry_url(package, version = nil)
      v = version.is_a?(String) ? version : version.try(:number)
      v ||= package.versions.first.try(:number)
      "https://packages.guix.gnu.org/packages/#{package.name}/#{v}/"
    end

    def install_command(package, version = nil)
      v = version.is_a?(String) ? version : version.try(:number)
      if v.present?
        "guix install #{package.name}@#{v}"
      else
        "guix install #{package.name}"
      end
    end

    def documentation_url(package, _version = nil)
      location = package.metadata&.dig('location')
      return nil unless location.present?

      file_path, line = location.split(':')
      "https://git.savannah.gnu.org/cgit/guix.git/tree/#{file_path}#n#{line}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return 'removed' if pkg.blank?
      nil
    end

    def packages_url
      "https://guix.gnu.org/packages.json"
    end

    def packages
      @@guix_packages_cache ||= load_packages_json
    end

    def self.clear_packages_cache!
      @@guix_packages_cache = nil
    end

    def load_packages_json
      response = get_raw(packages_url)
      raw = Oj.load(response)

      return {} if raw.nil? || !raw.is_a?(Array)

      index = {}
      raw.each do |entry|
        name = entry['name']
        next if name.blank?
        index[name] ||= []
        index[name] << entry
      end
      index
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      url = "https://git.savannah.gnu.org/cgit/guix.git/atom/?h=master"
      begin
        feed = SimpleRSS.parse(get_raw(url))
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

    def fetch_package_metadata_uncached(name)
      packages[name]
    end

    def package_metadata(name)
      entries = fetch_package_metadata(name)
      map_package_metadata(entries, name)
    end

    def map_package_metadata(entries, name = nil)
      return false if entries.blank?

      entries = entries.is_a?(Array) ? entries : [entries]
      latest = entries.max_by { |e| e['version'].to_s }
      return false if latest.blank?

      name ||= latest['name']

      {
        name: name,
        description: latest['synopsis'],
        homepage: latest['homepage'],
        repository_url: repo_fallback('', latest['homepage']),
        metadata: {
          location: latest['location'],
          variable_name: latest['variable_name'],
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      entries = fetch_package_metadata(pkg_metadata[:name])
      return [] if entries.blank?

      Array(entries).map do |entry|
        integrity = entry.dig('source', 0, 'integrity')

        {
          number: entry['version'],
          integrity: integrity,
          metadata: {
            variable_name: entry['variable_name'],
          }.compact
        }
      end
    end

    def maintainers_metadata(_name)
      []
    end

    def dependencies_metadata(_name, _version, _package)
      []
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: nil,
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
      }
    end
  end
end
