# frozen_string_literal: true

module Ecosystem
  class Conan < Base
    GITHUB_RAW_BASE = "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes"
    CONAN_CENTER_API = "https://center.conan.io"
    CONAN_IO_API = "https://conan.io/api"

    def registry_url(package, version = nil)
      version_part = version ? "?version=#{version}" : ""
      "https://conan.io/center/recipes/#{package.name}#{version_part}"
    end

    def install_command(package, version = nil)
      version_part = version ? "/#{version}" : ""
      "conan install --requires=#{package.name}#{version_part}"
    end

    def download_url(package, version)
      return nil unless version.present?
      version.metadata&.dig("url")
    end

    def documentation_url(package, version = nil)
      "https://conan.io/center/recipes/#{package.name}"
    end

    def check_status(package)
      name = package.is_a?(Package) ? package.name : package
      pkg_info = packages_data[name]
      return 'removed' unless pkg_info
      deprecated = pkg_info["deprecated"]
      return 'deprecated' if deprecated.present? && deprecated != "false" && deprecated != false
      nil
    end

    def all_package_names
      packages_data.keys.sort
    rescue StandardError
      []
    end

    def recently_updated_package_names
      url = "https://github.com/conan-io/conan-center-index/commits/master.atom"
      feed = SimpleRSS.parse(get_raw(url))
      titles = feed.items.map(&:title)
      titles.map { |t| t.match(/\[([^\]]+)\]/)&.[](1) }.compact.uniq.first(100)
    rescue StandardError
      []
    end

    def packages_data
      @packages_data ||= begin
        response = get("#{CONAN_IO_API}/search/all?topics=&licenses=")
        return {} unless response
        response.transform_values { |v| v }
               .values
               .to_h { |pkg| [pkg["name"], pkg["info"]] }
      end
    rescue StandardError
      {}
    end

    def fetch_package_metadata(name)
      api_info = packages_data[name]

      config = get_raw("#{GITHUB_RAW_BASE}/#{name}/config.yml") rescue nil
      parsed_config = config ? YAML.safe_load(config) : nil
      versions = parsed_config&.dig("versions")&.keys || []
      folder = parsed_config&.dig("versions", versions.first, "folder") || "all"
      conanfile = get_raw("#{GITHUB_RAW_BASE}/#{name}/#{folder}/conanfile.py") rescue nil

      {
        "name" => name,
        "versions" => versions,
        "folder" => folder,
        "conanfile" => conanfile,
        "api_info" => api_info
      }
    rescue StandardError
      nil
    end

    def map_package_metadata(pkg_metadata)
      return false unless pkg_metadata.present?

      api_info = pkg_metadata["api_info"]
      conanfile = pkg_metadata["conanfile"]
      parsed = conanfile ? parse_conanfile(conanfile) : {}

      description = api_info&.dig("description") || parsed[:description]
      licenses = api_info&.dig("licenses")&.keys&.join(",") || parsed[:license]
      keywords = api_info&.dig("labels")&.keys || parsed[:topics] || []

      {
        name: pkg_metadata["name"],
        description: description,
        homepage: parsed[:homepage],
        licenses: licenses,
        keywords_array: keywords,
        repository_url: repo_fallback(parsed[:url], parsed[:homepage]),
        versions: pkg_metadata["versions"],
        metadata: {
          folder: pkg_metadata["folder"]
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      return [] unless pkg_metadata.present? && pkg_metadata[:versions].present?

      conandata = begin
        raw = get_raw("#{GITHUB_RAW_BASE}/#{pkg_metadata[:name]}/#{pkg_metadata.dig(:metadata, :folder) || 'all'}/conandata.yml")
        YAML.safe_load(raw) if raw
      rescue StandardError
        nil
      end

      pkg_metadata[:versions].map do |version|
        sources = conandata&.dig("sources", version)
        url = if sources.is_a?(Hash)
          sources["url"].is_a?(Array) ? sources["url"].first : sources["url"]
        end
        sha256 = sources&.dig("sha256") if sources.is_a?(Hash)

        {
          number: version,
          metadata: {
            url: url,
            sha256: sha256
          }.compact
        }
      end
    end

    def dependencies_metadata(name, version, _package)
      use_it_data = get("#{CONAN_IO_API}/package/#{name}/use_it") rescue nil

      if use_it_data && use_it_data[version]
        version_data = use_it_data[version]["use_it"]
        return [] unless version_data

        deps = []
        (version_data["requires"] || []).each do |req|
          dep_name, requirement = parse_requirement(req)
          deps << {
            package_name: dep_name,
            requirements: requirement,
            kind: "runtime",
            ecosystem: self.class.name.demodulize.downcase
          }
        end

        (version_data["build_requires"] || []).each do |req|
          dep_name, requirement = parse_requirement(req)
          deps << {
            package_name: dep_name,
            requirements: requirement,
            kind: "development",
            ecosystem: self.class.name.demodulize.downcase
          }
        end

        return deps if deps.any?
      end

      folder = "all"
      conanfile = get_raw("#{GITHUB_RAW_BASE}/#{name}/#{folder}/conanfile.py")
      return [] unless conanfile
      parse_dependencies(conanfile)
    rescue StandardError
      []
    end

    def deprecation_info(name)
      api_info = packages_data[name]
      deprecated = api_info&.dig("deprecated")
      return nil if deprecated.nil? || deprecated == "false" || deprecated == false

      {
        is_deprecated: true,
        message: deprecated.is_a?(String) ? "Deprecated in favor of #{deprecated}" : "This package is deprecated"
      }
    rescue StandardError
      nil
    end

    def parse_conanfile(content)
      description = extract_field(content, "description")
      if description&.start_with?("(")
        description = content.match(/description\s*=\s*\((.*?)\)/m)&.[](1)&.gsub(/["'\s]+/, " ")&.strip
      end

      {
        description: description,
        homepage: extract_field(content, "homepage"),
        license: extract_field(content, "license"),
        url: extract_field(content, "url"),
        topics: extract_tuple(content, "topics")
      }
    end

    def extract_field(content, field)
      match = content.match(/^\s*#{field}\s*=\s*["']([^"']+)["']/m)
      match&.[](1)
    end

    def extract_tuple(content, field)
      match = content.match(/^\s*#{field}\s*=\s*\(([^)]+)\)/m)
      return [] unless match
      match[1].scan(/["']([^"']+)["']/).flatten
    end

    def parse_dependencies(content)
      deps = []

      content.scan(/self\.requires\(["']([^"']+)["']/).each do |match|
        dep_string = match[0]
        name, requirement = parse_requirement(dep_string)
        deps << {
          package_name: name,
          requirements: requirement,
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase
        }
      end

      content.scan(/self\.tool_requires\(["']([^"']+)["']/).each do |match|
        dep_string = match[0]
        name, requirement = parse_requirement(dep_string)
        deps << {
          package_name: name,
          requirements: requirement,
          kind: "development",
          ecosystem: self.class.name.demodulize.downcase
        }
      end

      deps
    end

    def parse_requirement(dep_string)
      if dep_string.include?("/")
        parts = dep_string.split("/")
        name = parts[0]
        version_part = parts[1]&.split("@")&.first
        requirement = version_part || "*"
      else
        name = dep_string
        requirement = "*"
      end
      [name, requirement]
    end
  end
end
