# frozen_string_literal: true

module Ecosystem
  class Wordpress < Base
    API_URL = "https://api.wordpress.org/plugins/info/1.2/".freeze

    def registry_url(package, _version = nil)
      "https://wordpress.org/plugins/#{package.name}/"
    end

    def download_url(package, version = nil)
      metadata = fetch_package_metadata(package.name)
      return metadata["download_link"] if version.blank?

      metadata.dig("versions", version.to_s)
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def install_command(package, _version = nil)
      "wp plugin install #{package.name}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg["slug"].present?

      "removed"
    end

    def all_package_names
      query_plugins(page: 1, per_page: 250).map { |plugin| plugin["slug"] }.compact
    rescue
      []
    end

    def recently_updated_package_names
      query_plugins(page: 1, per_page: 100, browse: "updated").map { |plugin| plugin["slug"] }.compact
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      request = URI.encode_www_form(
        "action" => "plugin_information",
        "request[slug]" => name,
        "request[fields][versions]" => 1
      )
      get_json("#{API_URL}?#{request}")
    rescue
      nil
    end

    def map_package_metadata(package)
      return false unless package.present?

      {
        name: package["slug"],
        description: package["short_description"].presence || package["name"],
        homepage: package["homepage"].presence || registry_url(Package.new(name: package["slug"])),
        repository_url: repo_fallback(package["homepage"], registry_url(Package.new(name: package["slug"]))),
        keywords_array: Array.wrap(package["tags"]).map { |tag| tag.is_a?(Array) ? tag.first : tag }.compact,
        licenses: "Unknown",
        downloads: package["downloaded"],
        downloads_period: "total",
        versions: package["versions"]&.keys || [],
        metadata: {
          "author" => package["author"],
          "author_profile" => package["author_profile"],
          "requires" => package["requires"],
          "requires_php" => package["requires_php"],
          "tested" => package["tested"],
          "rating" => package["rating"],
          "active_installs" => package["active_installs"]
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

    private

    def query_plugins(options = {})
      params = {
        "action" => "query_plugins",
        "request[page]" => options[:page] || 1,
        "request[per_page]" => options[:per_page] || 100,
        "request[fields][description]" => 0,
        "request[fields][sections]" => 0,
        "request[fields][versions]" => 0
      }
      params["request[browse]"] = options[:browse] if options[:browse]

      response = get_json("#{API_URL}?#{URI.encode_www_form(params)}")
      response["plugins"] || []
    end
  end
end
