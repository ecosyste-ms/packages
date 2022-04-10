# frozen_string_literal: true

module Ecosystem
  class Packagist < Base
    def package_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}##{version}"
    end

    def install_command(package, version = nil)
      "composer require #{package.name}" + (version ? ":#{version}" : "")
    end

    def all_package_names
      get("#{@registry_url}/packages/list.json")["packageNames"]
    end

    def recently_updated_package_names
      u = "#{@registry_url}/feeds/releases.rss"
      updated = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      u = "#{@registry_url}/feeds/packages.rss"
      new_packages = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      (updated.map { |t| t.split(" ").first } + new_packages).uniq
    end

    def fetch_package_metadata(name)
      get_json("#{@registry_url}/packages/#{name}.json")["package"]
    end

    def deprecation_info(name)
      is_deprecated = package(name).dig("abandoned") || ""

      {
        is_deprecated: is_deprecated != "",
        message: "",
      }
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.nil?
      return false unless pkg_metadata["versions"].any?

      # for version comparison of php, we want to reject any dev versions unless
      # there are only dev versions of the package
      versions = pkg_metadata["versions"].values.reject { |v| v["version"].include? "dev" }
      versions = pkg_metadata["versions"].values if versions.empty?
      # then we'll use the most recently published as our most recent version
      latest_version = versions.reject{|v| v['time'].blank? }.max_by { |v| v["time"] }
      return false if latest_version.nil?
      {
        name: latest_version["name"],
        description: latest_version["description"].try(:delete, "\u0000"),
        homepage: latest_version["home_page"],
        keywords_array: Array.wrap(latest_version["keywords"]),
        licenses: Array.wrap(latest_version["license"]).join(","),
        repository_url: repo_fallback(pkg_metadata["repository"], latest_version["home_page"]),
        versions: pkg_metadata["versions"],
      }
    end

    def versions_metadata(pkg_metadata)
      acceptable_versions(pkg_metadata).map do |k, v|
        {
          number: k,
          published_at: v["time"],
        }
      end
    end

    def acceptable_versions(pkg_metadata)
      pkg_metadata[:versions].select do |k, _v|
        # See: https://getcomposer.org/doc/articles/versions.md#branches
        (k =~ /^dev-.*/i).nil? && (k =~ /\.x-dev$/i).nil?
      end
    end

    def dependencies_metadata(_name, version, package)
      vers = package[:versions][version]
      return [] if vers.nil?

      map_dependencies(vers.fetch("require", {}).reject { |k, _v| k == "php" }, "runtime") +
        map_dependencies(vers.fetch("require-dev", {}).reject { |k, _v| k == "php" }, "Development")
    end
  end
end
