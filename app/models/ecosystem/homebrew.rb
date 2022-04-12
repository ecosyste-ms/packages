# frozen_string_literal: true

module Ecosystem
  class Homebrew < Base
    def package_url(db_package, _version = nil)
      "http://formulae.brew.sh/formula/#{db_package.name}"
    end

    def install_command(db_package, _version = nil)
      "brew install #{db_package.name}"
    end

    def all_package_names
      get("https://formulae.brew.sh/api/formula.json").map { |package| package["name"] }.uniq
    end

    def recently_updated_package_names
      u = "https://github.com/Homebrew/homebrew-core/commits/master.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(/[\s,:]/)[0] }.uniq
    end

    def fetch_package_metadata(name)
      get("https://formulae.brew.sh/api/formula/#{name}.json")
    end

    def map_package_metadata(package)
      {
        name: package["name"],
        description: package["desc"],
        homepage: package["homepage"],
        repository_url: repo_fallback("", package["homepage"]),
        licenses: package['license'],
        version: package.dig("versions", "stable"),
        dependencies: package["dependencies"],
        versions: package['versions']
      }
    end

    def versions_metadata(package)
      stable = package[:versions]["stable"]
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
          ecosystem: self.class.name.demodulize,
        }
      end
    end
  end
end
