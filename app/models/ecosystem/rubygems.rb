# frozen_string_literal: true

module Ecosystem
  class Rubygems < Base
    def package_url(package, version = nil)
      "#{@registry_url}/gems/#{package.name}" + (version ? "/versions/#{version}" : "")
    end

    def download_url(name, version)
      "#{@registry_url}/downloads/#{name}-#{version}.gem"
    end

    def documentation_url(name, version = nil)
      "http://www.rubydoc.info/gems/#{name}/#{version}"
    end

    def install_command(package, version = nil)
      "gem install #{package.name} -s #{@registry_url}" + (version ? " -v #{version}" : "")
    end

    def check_status_url(package)
      "#{@registry_url}/api/v1/versions/#{package.name}.json"
    end

    def all_package_names
      gems = Marshal.load(Gem::Util.gunzip(get_raw("#{@registry_url}/specs.4.8.gz")))
      gems.map(&:first).uniq
    end

    def recently_updated_package_names
      updated = get("#{@registry_url}/api/v1/activity/just_updated.json").map { |h| h["name"] }
      new_gems = get("#{@registry_url}/api/v1/activity/latest.json").map { |h| h["name"] }
      (updated + new_gems).uniq
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/api/v1/gems/#{name}.json")
    rescue StandardError
      {}
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata["name"].blank?
      {
        name: pkg_metadata["name"],
        description: pkg_metadata["info"],
        homepage: pkg_metadata["homepage_uri"],
        licenses: pkg_metadata.fetch("licenses", []).try(:join, ","),
        repository_url: repo_fallback(pkg_metadata["source_code_uri"], pkg_metadata["homepage_uri"]),
      }
    end

    def versions_metadata(pkg_metadata)
      json = get_json("#{@registry_url}/api/v1/versions/#{pkg_metadata[:name]}.json")
      json.map do |v|
        {
          number: v["number"],
          published_at: v["created_at"],
          licenses: v.fetch("licenses", []).try(:join, ","),
        }
      end
    rescue StandardError
      []
    end

    def dependencies_metadata(name, version, _package)
      json = get_json("#{@registry_url}/api/v2/rubygems/#{name}/versions/#{version}.json")

      deps = json["dependencies"]
      map_dependencies(deps["development"], "Development") + map_dependencies(deps["runtime"], "runtime")
    rescue StandardError
      []
    end

    def map_dependencies(deps, kind)
      deps.map do |dep|
        {
          package_name: dep["name"],
          requirements: dep["requirements"],
          kind: kind,
          ecosystem: self.class.name.demodulize,
        }
      end
    end
  end
end
