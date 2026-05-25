# frozen_string_literal: true

module Ecosystem
  class Drupal < Base
    API_URL = "https://www.drupal.org/api-d7/node.json".freeze

    def registry_url(package, _version = nil)
      "https://www.drupal.org/project/#{package.name}"
    end

    def download_url(package, version = nil)
      return nil unless version.present?

      "https://ftp.drupal.org/files/projects/#{package.name}-#{version}.tar.gz"
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, version = nil)
      version_part = version ? ":#{version}" : ""
      "composer require drupal/#{package.name}#{version_part}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg["field_project_machine_name"].present?

      "removed"
    end

    def all_package_names
      fetch_modules.map { |mod| module_name(mod) }.compact
    rescue
      []
    end

    def recently_updated_package_names
      fetch_modules(sort: "changed", direction: "DESC").map { |mod| module_name(mod) }.compact.first(100)
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      response = get_json("#{API_URL}?#{URI.encode_www_form(type: 'project_module', field_project_machine_name: name)}")
      Array.wrap(response["list"]).first
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package.present?

      name = module_name(package)
      homepage = package["url"].presence || registry_url(Package.new(name: name))

      {
        name: name,
        description: package["body"]&.dig("value") || package["title"],
        homepage: homepage,
        repository_url: repo_fallback(package["field_project_repository"], homepage),
        keywords_array: Array.wrap(package["taxonomy_vocabulary_3"]).map { |term| term["name"] || term }.compact,
        licenses: package["field_project_license"] || "GPL-2.0-or-later",
        downloads: package["field_project_download_count"],
        downloads_period: "total",
        versions: Array.wrap(package["field_project_releases"]).filter_map { |release| release["version"] || release["name"] },
        metadata: {
          "nid" => package["nid"],
          "title" => package["title"],
          "project_type" => package["field_project_type"],
          "created" => package["created"],
          "changed" => package["changed"],
          "maintainers" => package["field_project_maintainers"]
        }
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      pkg_metadata[:versions]
        .reject { |version| existing_version_numbers.include?(version) }
        .map do |version|
          {
            number: version,
            published_at: nil,
            licenses: pkg_metadata[:licenses],
            metadata: pkg_metadata[:metadata]
          }
        end
    end

    def purl_type
      "drupal"
    end

    def self.purl_type
      "drupal"
    end

    private

    def fetch_modules(sort: nil, direction: nil)
      params = { type: "project_module", limit: 100 }
      params[:sort] = sort if sort
      params[:direction] = direction if direction

      response = get_json("#{API_URL}?#{URI.encode_www_form(params)}")
      Array.wrap(response["list"])
    end

    def module_name(package)
      package["field_project_machine_name"].presence || package["machine_name"].presence || package["title"]&.parameterize
    end
  end
end
