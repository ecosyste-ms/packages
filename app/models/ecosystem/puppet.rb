# frozen_string_literal: true

module Ecosystem
  class Puppet < Base
    def all_package_names
      offset = 0
      packages = []
      loop do
        results = get_json("https://forgeapi.puppetlabs.com/v3/modules?limit=100&offset=#{offset}")["results"].map { |result| result["slug"] }
        break if results == []

        packages += results
        offset += 100
      end
      packages
    end

    def fetch_package_metadata(name)
      get_json("https://forgeapi.puppetlabs.com/v3/modules/#{name}")
    end

    def map_package_metadata(raw_package)
      current_release = raw_package["current_release"]
      metadata = current_release["metadata"]
      {
        name: raw_package["slug"],
        repository_url: metadata["source"],
        homepage: metadata["project_page"],
        description: metadata["summary"],
        keywords_array: current_release["tags"],
        licenses: metadata["license"],
        releases: raw_package['releases']
      }
    end

    def versions_metadata(raw_package)
      raw_package[:releases].map do |release|
        {
          number: release["version"],
          published_at: release["created_at"],
        }
      end
    end

    def dependencies_metadata(name, version, _mapped_package)
      release = get_json("https://forgeapi.puppetlabs.com/v3/releases/#{name}-#{version}")
      metadata = release["metadata"]
      metadata["dependencies"].map do |dependency|
        {
          package_name: dependency["name"].sub("/", "-"),
          requirements: dependency["version_requirement"],
          kind: "runtime",
          ecosystem: self.class.name.demodulize,
        }
      end
    end

    def recently_updated_package_names
      get_json("https://forgeapi.puppetlabs.com/v3/modules?limit=100&sort_by=latest_release")["results"].map { |result| result["slug"] }
    end

    def install_command(db_package, version = nil)
      "puppet module install #{db_package.name}" + (version ? " --version #{version}" : "")
    end

    def package_url(db_package, version = nil)
      "https://forge.puppet.com/#{db_package.name.sub('-', '/')}" + (version ? "/#{version}" : "")
    end

    def download_url(name, version = nil)
      "https://forge.puppet.com/v3/files/#{name}-#{version}.tar.gz"
    end
  end
end
