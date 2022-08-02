# frozen_string_literal: true

module Ecosystem
  class Puppet < Base
    def all_package_names
      offset = 0
      packages = []
      loop do
        results = get_json("#{@registry_url}/v3/modules?limit=100&offset=#{offset}")["results"].map { |result| result["slug"] }
        break if results == []

        packages += results
        offset += 100
      end
      packages
    rescue
      []
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/v3/modules/#{name}")
    rescue
      false
    end

    def map_package_metadata(package)
      return false unless package
      current_release = package["current_release"]
      return false if current_release.nil?
      metadata = current_release["metadata"]
      {
        name: package["slug"],
        repository_url: metadata["source"],
        homepage: metadata["project_page"],
        description: metadata["summary"],
        keywords_array: current_release["tags"],
        licenses: metadata["license"],
        releases: package['releases']
      }
    end

    def versions_metadata(package)
      package[:releases].map do |release|
        version = get_json("#{@registry_url}/v3/releases/#{package[:name]}-#{release["version"]}")
        integrity = version['file_sha256'] ? 'sha256-' + version['file_sha256'] : nil        
        {
          number: release["version"],
          published_at: release["created_at"],
          integrity: integrity
        }
      end
    end

    def dependencies_metadata(name, version, _mapped_package)
      release = get_json("#{@registry_url}/v3/releases/#{name}-#{version}")
      metadata = release["metadata"]
      metadata["dependencies"].map do |dependency|
        {
          package_name: dependency["name"].sub("/", "-"),
          requirements: dependency["version_requirement"],
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def recently_updated_package_names
      get_json("#{@registry_url}/v3/modules?limit=100&sort_by=latest_release")["results"].map { |result| result["slug"] }
    rescue
      []
    end

    def install_command(db_package, version = nil)
      "puppet module install #{db_package.name}" + (version ? " --version #{version}" : "")
    end

    def registry_url(db_package, version = nil)
      "#{@registry_url}/#{db_package.name.sub('-', '/')}" + (version ? "/#{version}" : "")
    end

    def download_url(package, version = nil)
      "#{@registry_url}/v3/files/#{package.name}-#{version}.tar.gz"
    end
  end
end
