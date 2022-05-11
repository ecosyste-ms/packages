# frozen_string_literal: true

module Ecosystem
  class Hex < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}/#{version}"
    end

    def download_url(package, version = nil)
      "https://repo.hex.pm/tarballs/#{package.name}-#{version}.tar"
    end

    def documentation_url(package, version = nil)
      "http://hexdocs.pm/#{package.name}/#{version}"
    end

    def install_command(package, version = nil)
      "mix hex.package fetch #{package.name} #{version}"
    end

    def all_package_names
      page = 1
      packages = []
      while page < 1000
        r = get("#{@registry_url}/api/packages?page=#{page}")
        break if r == []

        packages += r
        page += 1
      end
      packages.map { |package| package["name"] }
    end

    def recently_updated_package_names
      (get("#{@registry_url}/api/packages?sort=inserted_at").map { |package| package["name"] } +
      get("#{@registry_url}/api/packages?sort=updated_at").map { |package| package["name"] }).uniq
    end

    def fetch_package_metadata(name)
      get("#{@registry_url}/api/packages/#{name}")
    end

    def map_package_metadata(package)
      links = package["meta"].fetch("links", {}).each_with_object({}) do |(k, v), h|
        h[k.downcase] = v
      end
      {
        name: package["name"],
        homepage: links.except("github").first.try(:last),
        repository_url: links["github"],
        description: package["meta"]["description"],
        licenses: repo_fallback(package["meta"].fetch("licenses", []).join(","), links.except("github").first.try(:last)),
        releases: package['releases']
      }
    end

    def versions_metadata(package)
      package[:releases].map do |version|
        vers = get("#{@registry_url}/api/packages/#{package[:name]}/releases/#{version["version"]}")
        {
          number: version["version"],
          published_at: version["inserted_at"],
          integrity: "sha256-" + vers['checksum']
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      deps = get("#{@registry_url}/api/packages/#{name}/releases/#{version}")["requirements"]
      return [] if deps.nil?

      deps.map do |k, v|
        {
          package_name: k,
          requirements: v["requirement"],
          kind: "runtime",
          optional: v["optional"],
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end
  end
end
