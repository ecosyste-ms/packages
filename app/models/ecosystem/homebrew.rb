# frozen_string_literal: true

module Ecosystem
  class Homebrew < Base

    def self.purl_type
      'brew'
    end

    def registry_url(package, _version = nil)
      "https://formulae.brew.sh/formula/#{package.name}"
    end

    def install_command(package, _version = nil)
      "brew install #{package.name}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return nil if pkg.present? && pkg.is_a?(Hash) && pkg["name"].present?

      # Fall back to a direct request if not cached
      url = check_status_url(package)
      response = Faraday.head(url)
      return "removed" if [400, 404, 410].include?(response.status)
    end

    def all_package_names
      get("https://formulae.brew.sh/api/formula.json").map { |package| package["name"] }.uniq
    rescue
      []
    end

    def recently_updated_package_names
      u = "https://github.com/Homebrew/homebrew-core/commits/master.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(/[\s,:]/)[0] }.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      begin
        get("https://formulae.brew.sh/api/formula/#{name}.json")
      rescue
        {}
      end
    end

    def map_package_metadata(package)
      return false unless package.present?
      {
        name: package["name"],
        description: package["desc"],
        homepage: package["homepage"],
        repository_url: repo_fallback("", package["homepage"]),
        licenses: package['license'],
        version: package.dig("versions", "stable"),
        dependencies: package["dependencies"],
        versions: package['versions'],
        downloads: package['analytics']['install']['30d'][package['name']],
        downloads_period: 'last-month'
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      stable = pkg_metadata[:versions]["stable"]
      return [] if stable.blank?

      [
        {
          number: stable,
        },
      ]
    end

    def dependencies_metadata(_name, version, mapped_package)
      return nil unless version == mapped_package[:version]

      mapped_package[:dependencies].map do |dependency|
        {
          package_name: dependency,
          requirements: "*",
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end
  end
end
