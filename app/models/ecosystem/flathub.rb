# frozen_string_literal: true

module Ecosystem
  class Flathub < Base

    def has_dependent_repos?
      false
    end

    def self.purl_type
      'flatpak'
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/apps/#{package.name}"
    end

    def install_command(package, version = nil)
      "flatpak install flathub #{package.name}"
    end

    def documentation_url(package, version = nil)
      package.metadata&.dig('urls', 'help')
    end

    def check_status_url(package)
      "#{@registry_url}/api/v2/appstream/#{package.name}"
    end

    def all_package_names
      get_json("#{@registry_url}/api/v2/appstream")
    rescue
      []
    end

    def recently_updated_package_names
      updated = get_json("#{@registry_url}/api/v2/collection/recently-updated?page=1&per_page=100")['hits'] rescue []
      added = get_json("#{@registry_url}/api/v2/collection/recently-added?page=1&per_page=100")['hits'] rescue []
      (updated + added).map { |h| h['app_id'] }.compact.uniq
    end

    def fetch_package_metadata_uncached(name)
      app = get_json("#{@registry_url}/api/v2/appstream/#{name}")
      return nil if app.nil? || app['id'].blank?
      app['stats'] = get_json("#{@registry_url}/api/v2/stats/#{name}") rescue {}
      app
    rescue
      nil
    end

    def map_package_metadata(app)
      return false if app.blank? || app['id'].blank?

      urls = app['urls'] || {}
      flathub_metadata = app['metadata'] || {}
      bundle = app['bundle'] || {}

      {
        name: app['id'],
        description: app['summary'].presence || strip_html(app['description'])&.truncate(500),
        homepage: urls['homepage'],
        licenses: app['project_license'],
        repository_url: repo_fallback(urls['vcs_browser'], urls['homepage']),
        keywords_array: Array(app['categories']) + Array(app['keywords']),
        namespace: app['developer_name'],
        downloads: app.dig('stats', 'installs_total'),
        downloads_period: 'total',
        releases: app['releases'],
        metadata: {
          display_name: app['name'],
          type: app['type'],
          icon: app['icon'],
          runtime: bundle['runtime'],
          sdk: bundle['sdk'],
          urls: urls.compact,
          verified: flathub_metadata['flathub::verification::verified'],
          verification_method: flathub_metadata['flathub::verification::method'],
          is_eol: app['is_eol'],
          installs_last_month: app.dig('stats', 'installs_last_month'),
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      Array(pkg_metadata[:releases]).map do |release|
        next if release['version'].blank?
        {
          number: release['version'],
          published_at: release['timestamp'].present? ? Time.at(release['timestamp'].to_i) : nil,
          metadata: {
            release_type: release['type'],
            url: release['url'],
            urgency: release['urgency'],
          }.compact
        }
      end.compact
    end

    def dependencies_metadata(_name, version, mapped_package)
      return [] unless version == mapped_package[:releases]&.first&.dig('version')

      runtime = mapped_package.dig(:metadata, :runtime)
      sdk = mapped_package.dig(:metadata, :sdk)

      deps = []
      deps << runtime_dependency(runtime, 'runtime') if runtime.present?
      deps << runtime_dependency(sdk, 'build') if sdk.present?
      deps
    end

    def runtime_dependency(ref, kind)
      name, _arch, branch = ref.split('/')
      {
        package_name: name,
        requirements: branch.presence || '*',
        kind: kind,
        ecosystem: 'flathub',
      }
    end

    def strip_html(str)
      return nil if str.blank?
      Nokogiri::HTML(str).text.squish
    end
  end
end
