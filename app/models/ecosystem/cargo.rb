# frozen_string_literal: true

module Ecosystem
  class Cargo < Base
    def registry_url(package, version = nil)
      "#{@registry_url}/crates/#{package.name}/#{version}"
    end

    def install_command(package, version = nil)
      "cargo install #{package.name}" + (version ? " --version #{version}" : "")
    end

    def download_url(package, version)
      return nil unless version.present?
      "#{@registry_url}/api/v1/crates/#{package.name}/#{version}/download"
    end

    def documentation_url(package, version = nil)
      "https://docs.rs/#{package.name}/#{version}"
    end

    def check_status_url(package)
      "#{@registry_url}/api/v1/crates/#{package.name}"
    end

    def all_package_names
      page = 1
      packages = []
      loop do
        r = get("#{@registry_url}/api/v1/crates?page=#{page}&per_page=100")["crates"]
        break if r == []

        packages += r
        page += 1
      end
      packages.map { |package| package["name"] }
    rescue
      []
    end

    def recently_updated_package_names
      json = get("#{@registry_url}/api/v1/summary")
      updated_names = json["just_updated"].map { |c| c["name"] }
      new_names = json["new_crates"].map { |c| c["name"] }
      (updated_names + new_names).uniq
    rescue
      []
    end

    def fetch_package_metadata(name)
      get("#{@registry_url}/api/v1/crates/#{name}")
    end

    def map_package_metadata(package)
      return false unless package["versions"].present?
      latest_version = package["versions"].to_a.first
      {
        name: package["crate"]["id"],
        homepage: package["crate"]["homepage"],
        description: package["crate"]["description"],
        keywords_array: Array.wrap(package["crate"]["keywords"]),
        licenses: latest_version["license"],
        repository_url: repo_fallback(package["crate"]["repository"], package["crate"]["homepage"]),
        versions: package["versions"],
        downloads: package["crate"]["downloads"],
        downloads_period: 'total'
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].map do |version|
        {
          number: version["num"],
          published_at: version["created_at"],
          metadata: {
            downloads: version["downloads"],
          }
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      deps = get("#{@registry_url}/api/v1/crates/#{name}/#{version}/dependencies")["dependencies"]
      return [] if deps.nil?

      deps.map do |dep|
        {
          package_name: dep["crate_id"],
          requirements: dep["req"],
          kind: dep["kind"],
          optional: dep["optional"],
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def maintainers_metadata(name)
      json = get_json("#{@registry_url}/api/v1/crates/#{name}/owner_user")
      json['users'].map do |user|
        {
          uuid: user["id"],
          name: user["name"],
          login: user["login"],
          url: user["url"],
        }
      end.uniq{|m| m[:login]}
    rescue StandardError
      []
    end
  end
end
