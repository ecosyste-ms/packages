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
      "https://static.crates.io/crates/#{package.name}/#{package.name}-#{version}.crate"
    end

    def documentation_url(package, version = nil)
      "https://docs.rs/#{package.name}/#{version}"
    end

    def check_status_url(package)
      "#{@registry_url}/api/v1/crates/#{package.name}"
    end

    def check_status(package)
      json = fetch_package_metadata(package.name)
      return nil if json.present? && json.is_a?(Hash) && json["crate"].present?

      # Fall back to a direct request if not cached
      url = check_status_url(package)
      response = Faraday.get(url)
      return "removed" if [400, 404, 410].include?(response.status)
    end

    def all_package_names
      page = 1
      packages = []
      loop do
        r = get("#{@registry_url}/api/v1/crates?page=#{page}&per_page=100")["crates"]
        break if r.blank? || r == []

        packages += r
        page += 1
      end
      packages.map { |package| package["name"] }
    rescue
      []
    end

    def recently_updated_package_names
      json = get("#{@registry_url}/api/v1/summary")
      return [] if json.blank?
      updated_names = json["just_updated"].map { |c| c["name"] }
      new_names = json["new_crates"].map { |c| c["name"] }
      (updated_names + new_names).uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      get("#{@registry_url}/api/v1/crates/#{name}")
    rescue URI::InvalidURIError => e
      Rails.logger.warn "Invalid package name for Cargo: #{name.inspect} - #{e.message}"
      nil
    end

    def map_package_metadata(package)
      return false unless package.present? && package["versions"].present?
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
        downloads_period: 'total',
        metadata: {
          categories: package["crate"]["categories"],
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions].map do |version|
        {
          number: version["num"],
          published_at: version["created_at"],
          status: (version['yanked'] ? 'yanked' : nil),
          metadata: {
            uuid: version["id"],
            downloads: version["downloads"],
            published_by: version["published_by"],
            checksum: version["checksum"],
            size: version["size"],
            license: version["license"],
            crate_size: version["crate_size"],
            rust_version: version["rust_version"],
            features: version["features"],
            yanked: version["yanked"],
            yank_message: version["yank_message"],
            dl_path: version["dl_path"],
            audit_actions: version["audit_actions"],
            lib_links: version["lib_links"],
            has_lib: version["has_lib"],
            bin_names: version["bin_names"],
            edition: version["edition"]
          }
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      sleep 1
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
      return [] if json.blank?
      json['users'].map do |user|
        {
          uuid: user["id"],
          name: user["name"],
          login: user["login"],
          url: user["url"],
        }
      end.uniq{|m| m[:login]}.uniq{|m| m[:uuid]}
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "#{@registry_url}/users/#{maintainer.login}"
    end
  end
end
