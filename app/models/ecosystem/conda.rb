# frozen_string_literal: true

module Ecosystem
  class Conda < Base
    def registry_url(package, version = nil)
      "https://anaconda.org/#{@registry.metadata['kind']}/#{package.name}"
    end

    def download_url(package, version)
      return nil unless version.present?
      version.metadata["download_url"]
    end

    def install_command(package, version = nil)
      "conda install -c #{@registry.metadata['kind']} #{package.name}#{version ? "=" + version : ""}"
    end

    def check_status_url(package)
      "https://conda.libraries.io/package/#{package.name}"
    end

    def all_package_names
      all_packages.keys
    end

    def all_packages
      @all_packages ||= get_json("https://conda.libraries.io/#{@registry.metadata['key']}/")
    end

    def recently_updated_package_names
      all_packages.keys.filter do |name|
        all_packages[name]["versions"].any? { |version| version["published_at"].is_a?(String) && Time.parse(version["published_at"]) > 1.day.ago }
      end
    rescue
      []
    end

    def fetch_package_metadata(name)
      all_packages[name]
    rescue StandardError
      {}
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata["name"].blank?
      {
        name: pkg_metadata["name"],
        description: pkg_metadata["description"],
        homepage: pkg_metadata["homepage"],
        licenses: pkg_metadata["licenses"],
        repository_url: repo_fallback(pkg_metadata["repository_url"], pkg_metadata["homepage"]),
        versions: pkg_metadata['versions']
      }
    end

    def versions_metadata(pkg_metadata)
      pkg_metadata[:versions].map do |v|
        {
          number: v['number'],
          published_at: v["published_at"],
          licenses: v['original_license'],
          metadata: {
            arch: v["arch"],
            download_url: v["download_url"]
          }
        }
      end
    end

    def dependencies_metadata(name, version, package)
      version = package[:versions].find { |v| v['number'] == version }
      version['dependencies'].map do |dep|
        name, requirements = dep.split(' ')
        {
          package_name: name,
          requirements: requirements,
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end
  end
end
