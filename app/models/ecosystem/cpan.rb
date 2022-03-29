# frozen_string_literal: true

module Ecosystem
  class Cpan < Base
    def package_url(package, _version = nil)
      "https://metacpan.org/dist/#{package.name}"
    end

    def check_status_url(package)
      "https://metacpan.org/dist/#{package.name}"
    end

    def all_package_names
      packages = []
      size = 5000
      time = '1m'
      scroll_start_r = get("https://fastapi.metacpan.org/v1/release/_search?scroll=#{time}&size=#{size}&q=status:latest&fields=distribution")
      packages += scroll_start_r["hits"]["hits"]
      scroll_id = scroll_start_r['_scroll_id']
      loop do
        r = get("https://fastapi.metacpan.org/v1/_search/scroll?scroll=#{time}&scroll_id=#{scroll_id}")
        break if r["hits"]["hits"] == []

        packages += r["hits"]["hits"]
        scroll_id = r['_scroll_id']
      end
      packages.map { |package| package["fields"]["distribution"] }.flatten.uniq
    end

    def recently_updated_package_names
      names = get("https://fastapi.metacpan.org/v1/release/_search?q=status:latest&fields=distribution&sort=date:desc&size=100")["hits"]["hits"]
      names.map { |package| package["fields"]["distribution"] }.uniq
    end

    def fetch_package_metadata(name)
      get("https://fastapi.metacpan.org/v1/release/#{name}")
    end

    def map_package_metadata(raw_package)
      {
        name: raw_package["distribution"],
        homepage: raw_package.fetch("resources", {})["homepage"],
        description: raw_package["abstract"],
        licenses: raw_package.fetch("license", []).join(","),
        repository_url: repo_fallback(raw_package.fetch("resources", {}).fetch("repository", {})["web"], raw_package.fetch("resources", {})["homepage"]),
      }
    end

    def versions_metadata(raw_package)
      versions = get("https://fastapi.metacpan.org/v1/release/_search?q=distribution:#{raw_package[:name]}&size=5000&fields=version,date")["hits"]["hits"]
      versions.map do |version|
        {
          number: version["fields"]["version"],
          published_at: version["fields"]["date"],
        }
      end
    end

    def dependencies_metadata(name, version, _mapped_package)
      versions = get("https://fastapi.metacpan.org/v1/release/_search?q=distribution:#{name}&size=5000")["hits"]["hits"]
      # p versions
      version_data = versions.find { |v| v["_source"]["version"] == version }
      version_data["_source"]["dependency"].select { |dep| dep["relationship"] == "requires" }.map do |dep|
        {
          package_name: dep["module"].gsub("::", "-"),
          requirements: dep["version"],
          kind: dep["phase"],
          platform: self.class.name.demodulize,
        }
      end
    end
  end
end
