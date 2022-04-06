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
      get_raw("https://cdn.cocoapods.org/all_pods.txt").force_encoding('UTF-8').split("\n")
    end

    def recently_updated_package_names
      u = "https://github.com/CocoaPods/Specs/commits/master.atom"
      titles = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      titles.map { |t| t.split(" ")[1] }.uniq
    end

    def fetch_package_metadata(name)
      digest = Digest::MD5.hexdigest(name)
      chars = digest[0..2].split('')
      versions_lists = get_raw("https://cdn.cocoapods.org/all_pods_versions_#{chars.join('_')}.txt")
      lines = versions_lists.split("\n")
      pkg = lines.find do |line|
        line.split('/').first == name
      end
      return false if pkg.nil?
      versions = pkg.split('/')[1..-1]
      latest_version = versions.last

      json = get_json("https://cdn.cocoapods.org/Specs/#{chars.join('/')}/#{name}/#{latest_version}/#{name}.podspec.json")
      json["version_numbers"] = versions
      return json
    end

    def map_package_metadata(package)
      {
        name: package["name"],
        description: package["summary"],
        homepage: package["homepage"],
        licenses: parse_license(package["license"]),
        repository_url: repo_fallback(package.dig("source", "git"), ""),
        versions: package["version_numbers"]
      }
    end

    def versions_metadata(package)
      package.fetch(:versions, []).map do |v|
        {
          number: v,
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      digest = Digest::MD5.hexdigest(name)
      chars = digest[0..2].split('')
      json = get_json("https://cdn.cocoapods.org/Specs/#{chars.join('/')}/#{name}/#{version}/#{name}.podspec.json")
      map_dependencies(json['dependencies'], 'runtime')
    rescue StandardError
      []
    end

    def map_dependencies(deps, kind)
      deps.map do |k,v|
        {
          package_name: k,
          requirements: v.join(' ').presence || '*',
          kind: kind,
          ecosystem: self.class.name.demodulize,
        }
      end
    end

    def parse_license(package_license)
      package_license.is_a?(Hash) ? package_license["type"] : package_license
    end
  end
end
