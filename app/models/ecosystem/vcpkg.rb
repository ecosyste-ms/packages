# frozen_string_literal: true

module Ecosystem
  class Vcpkg < Base
    def install_command(package, _version = nil)
      ".\\vcpkg install #{package.name}"
    end

    def check_status(package)
      'removed' if fetch_package_metadata(package.name).nil?
    end

    def all_package_names
      @all_package_names ||= get_json('https://raw.githubusercontent.com/microsoft/vcpkg/master/versions/baseline.json').fetch('default').keys
    end

    def recently_updated_package_names
      u = "https://github.com/microsoft/vcpkg/commits/master.atom"
      titles = feed_titles(u)
      patterns = titles.filter_map { |title| title[/\A\[([^\]]+)\]/, 1] }
        .flat_map { |names| names.downcase.split(/[,\s]+/) }
      return [] if patterns.empty?

      names = all_package_names
      patterns.flat_map { |pattern| names.select { |name| File.fnmatch?(pattern, name) } }.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      response = request("https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/#{ERB::Util.url_encode(name)}/vcpkg.json")
      return nil if [404, 410].include?(response.status)
      raise "vcpkg manifest unavailable for #{name} (HTTP #{response.status})" unless response.success?

      JSON.parse(response.body)
    end

    def map_package_metadata(package)
      return false unless package.present? && package['name'].present?
      {
        name: package['name'],
        description: Array(package['description']).join(' '),
        homepage: package['homepage'],
        repository_url: repo_fallback('', package['homepage']),
        licenses: package['license'],
        version: package.values_at('version', 'version-semver', 'version-date', 'version-string').compact.first,
        dependencies: package['dependencies'],
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      return false unless pkg_metadata.present?
      [
        {
          number: pkg_metadata[:version],
        }
      ]
    end

    def dependencies_metadata(_name, version, mapped_package)
      return false unless mapped_package.present?
      return nil unless mapped_package[:version] == version
      return nil unless mapped_package[:dependencies].present?

      mapped_package[:dependencies].map do |dependency|
        name = dependency.is_a?(Hash) ? dependency['name'] : dependency
        if dependency.is_a?(Hash)
          if dependency['version>=']
            requirement = ">=#{dependency['version>=']}"
          else
            requirement = dependency['version'] || dependency['version-semver'] || dependency['version-date'] || dependency['version-string'] || '*'
          end
        else
          requirement = '*'
        end
        {
          package_name: name,
          requirements: requirement,
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end
  end
end
