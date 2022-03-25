# frozen_string_literal: true

module Ecosystem
  class Pypi < Base
    def package_url(package, version = nil)
      "#{@registry_url}/package/#{package.name}/#{version}"
    end

    def install_command(package, version = nil)
      "pip install #{package.name}" + (version ? "==#{version}" : "") + " --index-url #{@registry_url}/simple"
    end

    def documentation_url(name, version = nil)
      "https://#{name}.readthedocs.io/" + (version ? "en/#{version}" : "")
    end

    def formatted_name
      "PyPI"
    end

    def all_package_names
      index = Nokogiri::HTML(get_raw("#{@registry_url}/simple/"))
      index.css("a").map(&:text)
    end

    def recently_updated_package_names
      u = "#{@registry_url}/rss/updates.xml"
      updated = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      u = "#{@registry_url}/rss/packages.xml"
      new_packages = SimpleRSS.parse(get_raw(u)).items.map(&:title)
      (updated.map { |t| t.split(" ").first } + new_packages.map { |t| t.split(" ").first }).uniq
    end

    def fetch_package_metadata(name)
      get("#{@registry_url}/pypi/#{name}/json")
    rescue StandardError
      {}
    end

    def map_package_metadata(package)
      {
        name: package["info"]["name"],
        description: package["info"]["summary"],
        homepage: package["info"]["home_page"],
        keywords_array: Array.wrap(package["info"]["keywords"].try(:split, /[\s.,]+/)),
        licenses: licenses(package),
        repository_url: repo_fallback(
          package.dig("info", "package_urls", "Source").presence || package.dig("info", "package_urls", "Source Code"),
          package["info"]["home_page"].presence || package.dig("info", "package_urls", "Homepage")
        ),
        releases: package['releases']
      }
    end

    def versions_metadata(pkg_metadata)
      pkg_metadata[:releases].reject { |_k, v| v == [] }.map do |k, v|
        release = get("#{@registry_url}/pypi/#{pkg_metadata[:name]}/#{k}/json")
        {
          number: k,
          published_at: v[0]["upload_time"],
          licenses: release.dig("info", "license"),
        }
      end
    end

    def dependencies_metadata(_name, _version, _package)
      []
    end

    def licenses(package)
      return package["info"]["license"] if package["info"]["license"].present?

      license_classifiers = package["info"]["classifiers"].select { |c| c.start_with?("License :: ") }
      license_classifiers.map { |l| l.split(":: ").last }.join(",")
    end

    def package_find_names(package_name)
      [
        package_name,
        package_name.gsub("-", "_"),
        package_name.gsub("_", "-"),
      ]
    end
  end
end
