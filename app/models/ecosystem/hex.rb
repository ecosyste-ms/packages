# frozen_string_literal: true

module Ecosystem
  class Hex < Base
    def package_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}/#{version}"
    end

    def download_url(name, version = nil)
      "https://repo.hex.pm/tarballs/#{name}-#{version}.tar"
    end

    def documentation_url(name, version = nil)
      "http://hexdocs.pm/#{name}/#{version}"
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
      sleep 30
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

    def versions_metadata(package, _name)
      package[:releases].map do |version|
        {
          number: version["version"],
          published_at: version["inserted_at"],
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
          ecosystem: self.class.name.demodulize,
        }
      end
    end

    def download_registry_users(name)
      json = get_json("#{@registry_url}/api/packages/#{name}")
      json["owners"].map do |user|
        {
          uuid: "hex-" + user["username"],
          email: user["email"],
          login: user["username"],
        }
      end
    rescue StandardError
      []
    end

    def registry_user_url(login)
      "#{@registry_url}/users/#{login}"
    end
  end
end
