# frozen_string_literal: true

module Ecosystem
  class Easybuild < Base
    REPOSITORY = "easybuilders/easybuild-easyconfigs"
    BRANCH = "develop"

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def registry_url(package, version = nil)
      if version&.metadata&.dig("path").present?
        "https://github.com/#{REPOSITORY}/blob/#{BRANCH}/#{version.metadata['path']}"
      else
        "https://docs.easybuild.io/version-specific/supported-software/#{package.name.downcase}/"
      end
    end

    def install_command(package, version = nil)
      "eb #{package.name}" + (version ? "-#{version}.eb" : "")
    end

    def documentation_url(package, version = nil)
      registry_url(package, version)
    end

    def check_status(package)
      return "removed" if package_easyconfigs(package.name).empty?
    end

    def all_package_names
      easyconfig_paths.map { |path| path.split("/")[-2] }.compact.uniq.sort
    rescue
      []
    end

    def recently_updated_package_names
      feed = SimpleRSS.parse(get_raw("https://github.com/#{REPOSITORY}/commits/#{BRANCH}.atom"))
      feed.items.map { |item| item.title.scan(%r{easyconfigs/[a-z0-9]/([^/]+)/}).flatten }.flatten.uniq
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      paths = package_easyconfigs(name)
      latest_path = paths.max_by { |path| version_from_path(path, name).to_s }
      return {} if latest_path.blank?

      easyconfig = fetch_easyconfig(latest_path)
      parse_easyconfig(easyconfig).merge("name" => name, "path" => latest_path, "paths" => paths)
    rescue
      {}
    end

    def map_package_metadata(package)
      return false if package["name"].blank?

      {
        name: package["name"],
        description: package["description"],
        homepage: package["homepage"],
        repository_url: repo_fallback(package["homepage"], package["homepage"]),
        licenses: Array(package["license"]),
        metadata: {
          easyblock: package["easyblock"],
          toolchain: package["toolchain"],
          easyconfig_path: package["path"]
        }.compact,
        versions: package["paths"]
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:versions]).map do |path|
        version = version_from_path(path, pkg_metadata[:name])
        next if version.blank?

        metadata = parse_easyconfig(fetch_easyconfig(path))
        {
          number: version,
          metadata: {
            path: path,
            toolchain: metadata["toolchain"],
            versionsuffix: metadata["versionsuffix"],
            source_urls: metadata["source_urls"],
            sources: metadata["sources"]
          }.compact
        }
      end.compact
    rescue
      []
    end

    def dependencies_metadata(name, version, package)
      path = version&.metadata&.dig("path")
      return [] if path.blank?

      metadata = parse_easyconfig(fetch_easyconfig(path))
      Array(metadata["dependencies"]).map do |dependency|
        {
          package_name: dependency,
          requirements: "*",
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase
        }
      end
    rescue
      []
    end

    private

    def easyconfig_paths
      @easyconfig_paths ||= begin
        tree = get_json("https://api.github.com/repos/#{REPOSITORY}/git/trees/#{BRANCH}?recursive=1")
        Array(tree["tree"]).map { |node| node["path"] }.select { |path| path.end_with?(".eb") }
      end
    end

    def package_easyconfigs(name)
      first = name[0].downcase
      easyconfig_paths.select { |path| path.start_with?("easybuild/easyconfigs/#{first}/#{name}/") }
    end

    def fetch_easyconfig(path)
      get_raw("https://raw.githubusercontent.com/#{REPOSITORY}/#{BRANCH}/#{path}")
    end

    def version_from_path(path, name)
      file = File.basename(path, ".eb")
      file.delete_prefix("#{name}-").split("-").first
    end

    def parse_easyconfig(content)
      {
        "easyblock" => string_assignment(content, "easyblock"),
        "name" => string_assignment(content, "name"),
        "version" => string_assignment(content, "version"),
        "versionsuffix" => string_assignment(content, "versionsuffix"),
        "homepage" => string_assignment(content, "homepage"),
        "description" => string_assignment(content, "description"),
        "license" => string_assignment(content, "license"),
        "toolchain" => hash_assignment(content, "toolchain"),
        "source_urls" => list_assignment(content, "source_urls"),
        "sources" => list_assignment(content, "sources"),
        "dependencies" => dependencies_assignment(content)
      }.compact
    end

    def string_assignment(content, name)
      content[/^#{name}\s*=\s*(['"])(.*?)\1/m, 2] || content[/^#{name}\s*=\s*"""(.*?)"""/m, 1]&.strip
    end

    def hash_assignment(content, name)
      body = content[/^#{name}\s*=\s*\{([^\n]+)\}/, 1]
      return nil if body.blank?

      body.scan(/['"]([^'"]+)['"]\s*:\s*['"]([^'"]+)['"]/).to_h
    end

    def list_assignment(content, name)
      body = content[/^#{name}\s*=\s*\[(.*?)\]/m, 1]
      return [] if body.blank?

      body.scan(/['"]([^'"]+)['"]/).flatten
    end

    def dependencies_assignment(content)
      body = content[/^dependencies\s*=\s*\[(.*?)\]/m, 1]
      return [] if body.blank?

      body.scan(/\(\s*['"]([^'"]+)['"]/).flatten.uniq
    end
  end
end
