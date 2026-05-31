# frozen_string_literal: true

module Ecosystem
  class Winget < Base
    REPOSITORY = "microsoft/winget-pkgs"
    BRANCH = "master"

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def registry_url(package, version = nil)
      if version&.metadata&.dig("path").present?
        "https://github.com/#{REPOSITORY}/tree/#{BRANCH}/#{version.metadata['path']}"
      else
        "https://github.com/#{REPOSITORY}/tree/#{BRANCH}/#{package_path(package.name)}"
      end
    end

    def install_command(package, version = nil)
      "winget install --id #{package.name}" + (version ? " --version #{version}" : "")
    end

    def documentation_url(package, version = nil)
      registry_url(package, version)
    end

    def check_status(package)
      return "removed" if package_versions(package.name).empty?
    end

    def all_package_names
      manifest_paths.map { |path| identifier_from_path(path) }.compact.uniq.sort
    rescue
      []
    end

    def recently_updated_package_names
      feed = SimpleRSS.parse(get_raw("https://github.com/#{REPOSITORY}/commits/#{BRANCH}.atom"))
      feed.items.map { |item| item.title.scan(/Manifests\/[^:]+:\s+([^\s]+)/).flatten }.flatten.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      versions = package_versions(name)
      latest_path = versions.max_by { |path| File.basename(path) }
      return {} if latest_path.blank?

      metadata = fetch_version_manifest(name, latest_path)
      metadata.merge("name" => name, "path" => latest_path, "paths" => versions)
    rescue
      {}
    end

    def map_package_metadata(package)
      return false if package["name"].blank?

      {
        name: package["name"],
        description: package["Description"] || package["ShortDescription"],
        homepage: package["PackageUrl"] || package["PublisherUrl"],
        repository_url: repo_fallback(package["PackageUrl"], package["PublisherUrl"]),
        licenses: Array(package["License"]),
        keywords_array: Array(package["Tags"]),
        metadata: {
          publisher: package["Publisher"],
          moniker: package["Moniker"],
          manifest_path: package["path"]
        }.compact,
        versions: package["paths"]
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:versions]).map do |path|
        metadata = fetch_version_manifest(pkg_metadata[:name], path)
        version = metadata["PackageVersion"] || File.basename(path)
        {
          number: version,
          metadata: {
            path: path,
            manifest_version: metadata["ManifestVersion"],
            installer_type: metadata["InstallerType"],
            scope: metadata["Scope"]
          }.compact
        }
      end
    rescue
      []
    end

    private

    def manifest_paths
      @manifest_paths ||= begin
        tree = get_json("https://api.github.com/repos/#{REPOSITORY}/git/trees/#{BRANCH}?recursive=1")
        Array(tree["tree"]).map { |node| node["path"] }.select { |path| path.end_with?(".yaml") && path.start_with?("manifests/") }
      end
    end

    def package_path(name)
      parts = name.split(".")
      first = parts.first.to_s[0].downcase
      (["manifests", first] + parts).join("/")
    end

    def package_versions(name)
      prefix = package_path(name)
      manifest_paths.select do |path|
        path.start_with?("#{prefix}/") && path.end_with?("#{name}.yaml")
      end.map { |path| File.dirname(path) }.uniq
    end

    def identifier_from_path(path)
      File.basename(path, ".yaml") if path.match?(%r{/[^/]+/[^/]+\.yaml\z})
    end

    def fetch_version_manifest(name, path)
      base = path.delete_suffix("/")
      version_manifest = fetch_yaml("#{base}/#{name}.yaml")
      locale_manifest = fetch_first_yaml("#{base}/#{name}.locale.*.yaml")
      installer_manifest = fetch_first_yaml("#{base}/#{name}.installer.yaml")
      version_manifest.merge(locale_manifest).merge(installer_manifest)
    end

    def fetch_first_yaml(pattern)
      path = manifest_paths.find { |manifest_path| File.fnmatch(pattern, manifest_path) }
      path ? fetch_yaml(path) : {}
    end

    def fetch_yaml(path)
      YAML.safe_load(get_raw("https://raw.githubusercontent.com/#{REPOSITORY}/#{BRANCH}/#{path}")) || {}
    rescue
      {}
    end
  end
end
