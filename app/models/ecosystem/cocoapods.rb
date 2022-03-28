# frozen_string_literal: true

module Ecosystem
  class Cocoapods < Base
    def package_url(package, _version = nil)
      "#{registry_url}/pods/#{package.name}"
    end

    def documentation_url(name, version = nil)
      "https://cocoadocs.org/docsets/#{name}/#{version}"
    end

    def install_command(package, _version = nil)
      "pod try #{package.name}"
    end

    def all_package_names
      get_raw("https://cdn.cocoapods.org/all_pods.txt").split("\n")
    end

    def recently_updated_package_names
      u = "http://cocoapods.libraries.io/feed.rss"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(" ")[1] }.uniq
    end

    def fetch_package_metadata(name)
      versions = get_json("http://cocoapods.libraries.io/pods/#{name}.json") || {}
      # p versions
      latest_version = versions.keys.max_by { |version| version.split(".").map(&:to_i) }
      # p versions.keys
      # p latest_version
      versions.fetch(latest_version, {}).then do |v|
        v.merge("versions" => versions) if versions.present?
      end
    end

    def map_package_metadata(raw_package)
      {
        name: raw_package["name"],
        description: raw_package["summary"],
        homepage: raw_package["homepage"],
        licenses: parse_license(raw_package["license"]),
        repository_url: repo_fallback(raw_package.dig("source", "git"), ""),
        versions: raw_package["versions"]
      }
    end

    def versions_metadata(raw_package)
      raw_package.fetch(:versions, {}).keys.map do |v|
        {
          number: v.to_s,
        }
      end
    end

    def parse_license(package_license)
      package_license.is_a?(Hash) ? package_license["type"] : package_license
    end
  end
end
