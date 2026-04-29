# frozen_string_literal: true

module Ecosystem
  class Buildkite < Base

    def self.purl_type
      'buildkite'
    end

    def self.namespace_separator
      '/'
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: package.name.split('/').first,
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode, 'iso-8859-1', invalid: :replace, undef: :replace, replace: '')
      }
    end

    def registry_url(package, _version = nil)
      "https://buildkite.com/resources/plugins/#{plugin_slug(package.name)}"
    end

    def documentation_url(package, version = nil)
      version.present? ? "#{repository_url(package.name)}/tree/#{version.number}" : repository_url(package.name)
    end

    def download_url(package, version = nil)
      ref = version.try(:number).presence || 'HEAD'
      "https://codeload.github.com/#{repository_full_name(package.name)}/tar.gz/#{ref}"
    end

    def install_command(package, version = nil)
      version_number = version.try(:number).presence || version
      plugin = version_number.present? ? "#{package.name}##{version_number}" : package.name
      "plugins:\n  - #{plugin}: ~"
    end

    def check_status_url(package)
      repository_url(package.name)
    end

    def all_package_names
      scrape_plugin_names
    rescue
      []
    end

    def recently_updated_package_names
      all_package_names.first(20)
    end

    def fetch_package_metadata_uncached(name)
      repo = get_json("https://repos.ecosyste.ms/api/v1/repositories/lookup?url=#{CGI.escape(repository_url(name))}")
      return nil if repo.blank? || repo['error'].present?

      repo.merge('name' => name, 'repository_url' => repository_url(name))
    rescue
      nil
    end

    def map_package_metadata(package)
      return nil unless package

      {
        name: package['name'],
        description: package['description'],
        repository_url: package['repository_url'],
        licenses: package['license'],
        keywords_array: package['topics'],
        homepage: package['homepage'],
        tags_url: package['tags_url'],
        namespace: package['owner'],
        metadata: {
          default_branch: package['default_branch'],
          full_name: package['full_name']
        }
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      return [] unless pkg_metadata[:tags_url]
      tags_json = get_json("#{pkg_metadata[:tags_url]}?per_page=1000")
      return [] if tags_json.blank?

      tags_json.map do |tag|
        {
          number: tag['name'],
          published_at: tag['published_at'],
          metadata: {
            sha: tag['sha'],
            download_url: tag['download_url']
          }
        }
      end
    end

    def package_find_names(package_name)
      [package_name, repository_full_name(package_name)].uniq
    end

    private

    def repository_full_name(name)
      owner, plugin = name.split('/', 2)
      return name unless owner.present? && plugin.present?

      "#{owner}/#{plugin}-buildkite-plugin"
    end

    def repository_url(name)
      "https://github.com/#{repository_full_name(name)}"
    end

    def plugin_slug(name)
      name.tr('/', '-')
    end

    def scrape_plugin_names
      html = get_raw('https://buildkite.com/resources/plugins')
      html.scan(%r{github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)-buildkite-plugin}).map do |owner, plugin|
        "#{owner}/#{plugin}"
      end.uniq
    end
  end
end
