# frozen_string_literal: true

module Ecosystem
  class Rubygems < Base
    HAS_VERSIONS = true
    HAS_DEPENDENCIES = true
    HAS_OWNERS = true

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

    def package(name)
      get_json("#{@registry_url}/api/v1/gems/#{name}.json")
    rescue StandardError
      {}
    end

    def mapping(package)
      {
        name: package["name"],
        description: package["info"],
        homepage: package["homepage_uri"],
        licenses: package.fetch("licenses", []).try(:join, ","),
        repository_url: repo_fallback(package["source_code_uri"], package["homepage_uri"]),
      }
    end

    def versions(package, _name)
      json = get_json("#{@registry_url}/api/v1/versions/#{package['name']}.json")
      json.map do |v|
        {
          number: v["number"],
          published_at: v["created_at"],
          original_license: v.fetch("licenses"),
        }
      end
    rescue StandardError
      []
    end

    def dependencies(name, version, _package)
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
          platform: name.demodulize,
        }
      end
    end

    def download_registry_users(name)
      json = get_json("#{@registry_url}/api/v1/gems/#{name}/owners.json")
      json.map do |user|
        {
          uuid: user["id"],
          email: user["email"],
          login: user["handle"],
        }
      end
    rescue StandardError
      []
    end

    def registry_user_url(login)
      "#{@registry_url}/profiles/#{login}"
    end
  end
end
