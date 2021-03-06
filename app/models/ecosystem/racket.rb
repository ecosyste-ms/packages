# frozen_string_literal: true
module Ecosystem
  class Racket < Base
    def package_link(package, version = nil)
      "#{@registry_url}/package/#{package.name}"
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/package/#{package.name}"
    end

    def documentation_url(package, version = nil)
      "https://docs.racket-lang.org/#{package.name}/index.html"
    end

    def download_url(package, version = nil)
      return nil if package.repository_url.blank?
      return nil unless package.repository_url.include?('/github.com/')
      full_name = package.repository_url.gsub('https://github.com/', '')
      "https://codeload.github.com/#{full_name}/tar.gz/refs/heads/master"
    end

    def recently_updated_package_names
      all_package_data.sort_by{|k,v| -v["last-updated"]}.first(100).map(&:first)
    end

    def all_package_names
      all_package_data.keys
    end

    def all_package_data
      get_json("https://pkgs.racket-lang.org/pkgs-all.json.gz")
    end

    def install_command(package, version = nil)
      "raco pkg install #{package.name}"
    end

    def fetch_package_metadata(name)
      all_package_data[name]
    end

    def map_package_metadata(pkg)
      return false unless pkg
      {
        name: pkg["name"],
        repository_url: repo_fallback("", pkg["source"]),
        description: pkg['description'],
        keywords_array: pkg['tags']
      }
    end

    def homepage_link(page)
      page.at('a:contains("Code")') || page.at('th:contains("Documentation")').parent.css('a').first
    end

    def versions_metadata(package)
      [] # unsupported
    end
  end
end
