# frozen_string_literal: true

module Ecosystem
  class Bazel < Base
    BAZEL_CENTRAL_REGISTRY_BASE_GITHUB_TREE_URL = "https://api.github.com/repos/bazelbuild/bazel-central-registry/git/trees".freeze
    BAZEL_CENTRAL_REGISTRY_GITHUB_BASE = "https://raw.githubusercontent.com/bazelbuild/bazel-central-registry/main".freeze
    # This URL is for the registry itself (API), unlike https://registry.bazel.build that is just UI app for the registry
    BAZEL_CENTRAL_REGISTRY_URL = "https://bcr.bazel.build".freeze
    DEFAULT_MODULE_TYPE = "archive".freeze
    GIT_REPOSITORY_MODULE_TYPE = "git_repository".freeze
    RECENTLY_UPDATED_SECTION_XPATH = "//h2[contains(@class, 'font-bold') " \
      "and contains(@class, 'text-lg') and normalize-space(text())='Recently updated']/following-sibling::*[1][contains(@class, "\
      "'grid grid-cols-1')]".freeze

    def registry_url(package, version = nil)
      version_part = version ? "/#{version}" : ""
      "#{@registry_url}/modules/#{package.name}#{version_part}"
    end

    def install_command(package, version = nil)
      version_part = version ? ", version = \"#{version}\"" : ""
      "bazel_dep(name = \"#{package.name}\"#{version_part})"
    end

    def download_url(package, version)
      return nil unless version.present?

      # For supported types of modules check https://bazel.build/external/registry#source-json
      return version.metadata["remote"] if version.metadata["type"] == GIT_REPOSITORY_MODULE_TYPE

      version.metadata["url"]
    end

    def documentation_url(package, version = nil)
      # The "docs_url" field is optional according to the registry contribution guidelines:
      # https://github.com/bazelbuild/bazel-central-registry/blob/e258c1c26ec09ba0cefb05377b4a2516644060ca/docs/stardoc.md#publishing-the-docs
      version_part = version ? "/#{version}" : ""
      "https://registry.bazel.build/docs/#{package.name}#{version_part}"
    end

    def all_package_names
      github_modules_tree.map { |package| package["path"] }.compact
    rescue StandardError
      []
    end

    def recently_updated_package_names
      doc = get_html("https://registry.bazel.build/")
      modules_table = doc.at_xpath(RECENTLY_UPDATED_SECTION_XPATH)
      names = modules_table.css('a div.font-bold').map { |div| div.text.strip }
    rescue StandardError
      []
    end

    def fetch_package_metadata(name)
      fetched_data = get("#{BAZEL_CENTRAL_REGISTRY_URL}/modules/#{name}/metadata.json")
      {
        "name" => name,
        **fetched_data
      }
    rescue StandardError
      {}
    end

    def map_package_metadata(pkg_metadata)
      return false unless pkg_metadata.present?
      {
        name: pkg_metadata["name"],
        homepage: pkg_metadata["homepage"],
        repository_url: repo_fallback(pkg_metadata["repository"]&.first, pkg_metadata["homepage"]),
        versions: pkg_metadata["versions"],
        metadata: {
          maintainers: pkg_metadata["maintainers"],
          yanked_versions: pkg_metadata["yanked_versions"],
          deprecated: pkg_metadata["deprecated"],
          repository: pkg_metadata["repository"]
        }
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      # The package version metadata's specification: https://bazel.build/external/registry#source-json
      yanked_versions = pkg_metadata.dig(:metadata, :yanked_versions)&.keys

      pkg_metadata[:versions].map do |version|
        source = fetch_package_version_metadata(pkg_metadata[:name], version)
        {
          number: version,
          status: (yanked_versions.include?(version) ? "yanked" : nil),
          integrity: source["integrity"],
          metadata: if source["type"] == GIT_REPOSITORY_MODULE_TYPE
            {
              type: GIT_REPOSITORY_MODULE_TYPE,
              patch_strip: source["patch_strip"],
              patches: source["patches"],
              strip_prefix: source["strip_prefix"],
              # This module type's specific fields
              remote: source["remote"],
              commit: source["commit"],
              shallow_since: source["shallow_since"],
              tag: source["tag"],
              init_submodules: source["init_submodules"],
              verbose: source["verbose"],
            }
          else
            {
              type: DEFAULT_MODULE_TYPE,
              patch_strip: source["patch_strip"],
              patches: source["patches"],
              strip_prefix: source["strip_prefix"],
              # This module type's specific fields
              url: source["url"],
              mirror_urls: source["mirror_urls"],
              overlay: source["overlay"],
              archive_type: source["archive_type"]
            }
          end
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      module_verison_data = get_raw("#{BAZEL_CENTRAL_REGISTRY_URL}/modules/#{name}/#{version}/MODULE.bazel")
      Bibliothecary::Parsers::Bazel.parse_module_bazel(module_verison_data).dependencies.map do |dep|
        {
          package_name: dep[:name],
          requirements: dep[:requirement],
          kind: dep[:type],
          ecosystem: self.class.name.demodulize.downcase
        }
      end
    rescue StandardError
      []
    end

    def maintainers_metadata(name)
      fetched_data = get("#{BAZEL_CENTRAL_REGISTRY_URL}/modules/#{name}/metadata.json")
      return [] if fetched_data.blank?
      fetched_data['maintainers'].map do |user|
        {
          uuid: user["github_user_id"],
          name: user["name"],
          login: user["github"],
          email: user["email"],
          do_not_notify: user["do_not_notify"]
        }
      end.uniq{|m| m[:login]}.uniq{|m| m[:uuid]}
    rescue StandardError
      []
    end

    private

    def github_modules_tree
      modules_tree = github_registry_root_tree.find { |tree_entry| tree_entry["path"] == "modules" && tree_entry["type"] == "tree" }
      modules_tree = get_json("#{BAZEL_CENTRAL_REGISTRY_BASE_GITHUB_TREE_URL}/#{modules_tree["sha"]}", headers: github_tree_api_headers)
      modules_tree["tree"].select { |tree_entry| tree_entry.is_a?(Hash) && tree_entry["type"] == "tree" }
    end

    def github_registry_root_tree
      root_tree = get_json("#{BAZEL_CENTRAL_REGISTRY_BASE_GITHUB_TREE_URL}/main", headers: github_tree_api_headers)
      root_tree["tree"]
    end

    def github_tree_api_headers
      { "Accept" => "application/vnd.github+json" }
    end

    def fetch_package_version_metadata(name, version)
      get_json("#{BAZEL_CENTRAL_REGISTRY_URL}/modules/#{name}/#{version}/source.json")
    rescue StandardError
      {}
    end
  end
end
