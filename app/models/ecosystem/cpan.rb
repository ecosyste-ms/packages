# frozen_string_literal: true

module Ecosystem
  class Cpan < Base
    def registry_url(package, _version = nil)
      "https://metacpan.org/dist/#{package.name}"
    end

    def check_status_url(package)
      "https://metacpan.org/dist/#{package.name}"
    end

    def download_url(package, version)
      return nil unless version.present?
      return version.metadata["download_url"] if version.metadata["download_url"].present?
      author = package.metadata["author"]
      return nil if author.nil?
      "https://cpan.metacpan.org/authors/id/#{author[0]}/#{author[0..1]}/#{author}/#{package.name}-#{version}.tar.gz"
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
    rescue
      []
    end

    def recently_updated_package_names
      names = get("https://fastapi.metacpan.org/v1/release/_search?q=status:latest&fields=distribution&sort=date:desc&size=100")["hits"]["hits"]
      names.map { |package| package["fields"]["distribution"] }.uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      get("https://fastapi.metacpan.org/v1/release/#{name}")
    end

    def map_package_metadata(package)
      return nil if package["distribution"].nil?
      {
        name: package["distribution"],
        homepage: package.fetch("resources", {})["homepage"],
        description: package["abstract"],
        licenses: package.fetch("license", []).join(","),
        repository_url: repo_fallback(package.fetch("resources", {}).fetch("repository", {})["web"], package.fetch("resources", {})["homepage"]),
        keywords_array: package.fetch("metadata", {})["keywords"],
        metadata:{
          author: package['author']
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      versions = get("https://fastapi.metacpan.org/v1/release/_search?q=distribution:#{pkg_metadata[:name]}&size=5000")["hits"]["hits"]
      versions.map do |version|
        {
          number: version["_source"]["version"],
          published_at: version["_source"]["date"],
          integrity: "sha256-"+version["_source"]['checksum_sha256'],
          metadata: {
            download_url: version["_source"]["download_url"]
          }
        }
      end
    rescue
      []
    end

    def dependencies_metadata(name, version, _package)
      versions = get("https://fastapi.metacpan.org/v1/release/_search?q=distribution:#{name}&size=5000")["hits"]["hits"]
      version_data = versions.find { |v| v["_source"]["version"] == version }
      version_data["_source"]["dependency"].select { |dep| dep["relationship"] == "requires" }.map do |dep|
        {
          package_name: dep["module"].gsub("::", "-"),
          requirements: dep["version"],
          kind: dep["phase"],
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def maintainers_metadata(name)
      pkg = get("https://fastapi.metacpan.org/v1/release/#{name}")
      return unless pkg && pkg["author"].present?
      author = get("https://fastapi.metacpan.org/author/#{pkg["author"]}")
      return unless author 
      [
        {
          uuid: author["pauseid"],
          login: author["pauseid"],
          name: author["name"],
          email: Array(author["email"]).join(','),
          url: author['website'].first
        }
      ]
    end
  end
end
