module Ecosystem
  class Elm < Base
    def registry_url(package, version = nil)
      "https://package.elm-lang.org/packages/#{package.name}/#{version || 'latest'}"
    end

    def download_url(name, version = "master")
      "https://github.com/#{name}/archive/#{version}.zip"
    end

    def install_command(package, version = nil)
      "elm-package install #{package.name} #{version}"
    end

    def all_package_names
      packages.keys
    end

    def packages
      @packages ||= get("https://package.elm-lang.org/all-packages")
    end

    def recently_updated_package_names
      get("https://package.elm-lang.org/all-packages/since/1").map{|name| name.split('@').first }.uniq
    end

    def fetch_package_metadata(name)
      versions = get("https://package.elm-lang.org/packages/#{name}/releases.json") # get list of version numbers first
      latest_version = versions.keys.last
      get("https://package.elm-lang.org/packages/#{name}/#{latest_version}/elm.json")
    end

    def map_package_metadata(package)
      {
        name: package["name"],
        description: package["summary"],
        licenses: package['license'],
        repository_url: "https://github.com/#{package['name']}",
      }
    end

    def versions_metadata(_package, name)
      get("https://package.elm-lang.org/packages/#{name}/releases.json")
        .map do |version, timestamp|
          {
            number: version,
            published_at: Time.at(timestamp),
          }
        end
    end

    def dependencies_metadata(name, version, _mapped_package)
      get("https://package.elm-lang.org/packages/#{name}/#{version}/elm.json")
        .fetch("dependencies", {})
        .map do |name, requirement|
          {
            package_name: name,
            requirements: requirement,
            kind: "runtime",
            platform: self.class.name.demodulize,
          }
        end
    end
  end
end
