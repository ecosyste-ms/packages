# frozen_string_literal: true
module Ecosystem
  class Racket < Base
    def sync_maintainers_inline?
      true
    end

    def package_link(package, version = nil)
      "#{@registry_url}/package/#{package.name}"
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/package/#{package.name}"
    end

    def check_status(package)
      url = check_status_url(package)
      connection = Faraday.new do |faraday|
        faraday.use Faraday::FollowRedirects::Middleware
        faraday.adapter Faraday.default_adapter
      end

      response = connection.head(url)
      return "removed" if [400, 404, 410].include?(response.status)
      return 'removed' if fetch_package_metadata(package.name).nil?
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
      @all_package_data ||= get_json("https://pkgs.racket-lang.org/pkgs-all.json.gz")
    rescue
      {}
    end

    def install_command(package, version = nil)
      "raco pkg install #{package.name}"
    end

    def fetch_package_metadata_uncached(name)
      all_package_data[name]
    end

    def map_package_metadata(pkg)
      return false unless pkg
      {
        name: pkg["name"],
        repository_url: repo_fallback("", pkg["source"]),
        description: pkg['description'],
        keywords_array: pkg['tags'].reject(&:blank?)
      }
    end

    def homepage_link(page)
      page.at('a:contains("Code")') || page.at('th:contains("Documentation")').parent.css('a').first
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      [] # unsupported
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] unless pkg
      pkg["authors"].map do |email|
        {
          uuid: email,
          email: email
        }
      end
    end
  end
end
