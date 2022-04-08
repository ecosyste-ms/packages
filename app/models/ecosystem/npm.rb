# frozen_string_literal: true

module Ecosystem
  class Npm < Base
    def package_url(package, version = nil)
      "https://www.npmjs.com/package/#{package.name}" + (version ? "/v/#{version}" : "")
    end

    def download_url(name, version = nil)
      "#{@registry_url}/#{name}/-/#{name}-#{version}.tgz"
    end

    def install_command(package, version = nil)
      "npm install #{package.name}" + (version ? "@#{version}" : "")
    end

    def formatted_name
      "npm"
    end

    def all_package_names
      get("https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json")
    end

    def recently_updated_package_names
      u = "#{@registry_url}/-/rss?descending=true&limit=50"
      SimpleRSS.parse(get_raw(u)).items.map(&:title).uniq
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/#{name.gsub('/', '%2F')}")
    end

    def deprecation_info(name)
      versions = package(name)["versions"].values

      {
        is_deprecated: versions.all? { |v| v["deprecated"] },
        message: versions.last["deprecated"],
      }
    end

    def map_package_metadata(package)
      return false unless package["versions"].present?

      latest_version = package["versions"].to_a.last[1]

      repo = latest_version.fetch("repository", {})
      repo = repo[0] if repo.is_a?(Array)
      repo_url = repo.try(:fetch, "url", nil)

      {
        name: package["name"],
        description: latest_version["description"].try(:delete, "\u0000"),
        homepage: package["homepage"],
        keywords_array: Array.wrap(latest_version.fetch("keywords", [])).flatten,
        licenses: licenses(latest_version),
        repository_url: repo_fallback(repo_url, package["homepage"]),
        versions: package["versions"],
      }
    end

    def licenses(latest_version)
      license = latest_version.fetch("license", nil)
      if license.present?
        if license.is_a?(Hash)
          license.fetch("type", "")
        else
          license
        end
      else
        licenses = Array(latest_version.fetch("licenses", []))
        licenses.map do |lice|
          if lice.is_a?(Hash)
            lice.fetch("type", "")
          else
            lice
          end
        end.join(",")
      end
    end

    def versions_metadata(package)
      # npm license fields are supposed to be SPDX expressions now https://docs.npmjs.com/files/package.json#license
      package[:versions].map do |k, v|
        license = v.fetch("license", nil)
        license = licenses(v) unless license.is_a?(String)
        {
          number: k,
          published_at: package.fetch("time", {}).fetch(k, nil),
          licenses: license,
        }
      end
    end

    def dependencies_metadata(_name, version, package)
      vers = package[:versions][version]
      return [] if vers.nil?

      map_dependencies(vers.fetch("dependencies", {}), "runtime") +
        map_dependencies(vers.fetch("devDependencies", {}), "Development") +
        map_dependencies(vers.fetch("optionalDependencies", {}), "Optional", true)
    end
  end
end
