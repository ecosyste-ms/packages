# frozen_string_literal: true

module Ecosystem
  class Snap < Base
    API_URL = 'https://api.snapcraft.io'
    FIELDS = %w[
      title summary description license contact website publisher categories links
      store-url snap-id revision version download created-at base confinement type
    ].join(',').freeze

    def has_dependent_repos?
      false
    end

    def sync_maintainers_inline?
      true
    end

    def self.purl_type
      'snap'
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/#{package.name}"
    end

    def install_command(package, version = nil)
      "snap install #{package.name}"
    end

    def download_url(package, version)
      return nil unless version.present?
      version.metadata&.dig('download_url')
    end

    def check_status_url(package)
      "#{API_URL}/v2/snaps/info/#{package.name}"
    end

    def check_status(package)
      resp = request(check_status_url(package), headers: snap_headers)
      "removed" if [400, 404, 410].include?(resp.status)
    rescue
      nil
    end

    def sitemap
      @sitemap ||= begin
        doc = get_xml("#{@registry_url}/store/sitemap.xml")
        doc.remove_namespaces!
        doc.css('url').filter_map do |u|
          loc = u.at_css('loc')&.text
          next unless loc&.match?(%r{\Ahttps://snapcraft\.io/[^/]+\z})
          name = loc.split('/').last
          next if %w[store search about].include?(name)
          { name: name, lastmod: u.at_css('lastmod')&.text }
        end
      end
    end

    def all_package_names
      sitemap.map { |e| e[:name] }
    rescue
      []
    end

    def recently_updated_package_names
      sitemap.sort_by { |e| e[:lastmod].to_s }.reverse.first(100).map { |e| e[:name] }
    rescue
      []
    end

    def fetch_package_metadata_uncached(name)
      data = get_json("#{API_URL}/v2/snaps/info/#{CGI.escape(name)}?fields=#{FIELDS}", headers: snap_headers)
      return nil if data.nil? || data['error-list'].present? || data['name'].blank?
      data
    rescue
      nil
    end

    def map_package_metadata(data)
      return false if data.blank? || data['name'].blank?

      snap = data['snap'] || {}
      links = snap['links'] || {}
      publisher = snap['publisher'] || {}

      {
        name: data['name'],
        description: snap['summary'].presence || snap['description']&.truncate(500),
        homepage: snap['website'].presence || Array(links['website']).first,
        licenses: snap['license'],
        repository_url: repo_fallback(Array(links['source']).first, snap['website']),
        keywords_array: Array(snap['categories']).map { |c| c['name'] }.compact,
        namespace: publisher['username'],
        channel_map: data['channel-map'],
        metadata: {
          title: snap['title'],
          snap_id: data['snap-id'],
          store_url: snap['store-url'],
          publisher: publisher,
          contact: snap['contact'].presence || Array(links['contact']).first,
          links: links,
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      grouped = Array(pkg_metadata[:channel_map]).group_by { |c| c['version'] }
      grouped.filter_map do |version, entries|
        next if version.blank?
        primary = entries.find { |e| e.dig('channel', 'architecture') == 'amd64' } || entries.first
        {
          number: version,
          published_at: entries.map { |e| e.dig('channel', 'released-at') }.compact.min,
          integrity: integrity(primary),
          metadata: {
            revision: primary['revision'],
            base: primary['base'],
            confinement: primary['confinement'],
            type: primary['type'],
            size: primary.dig('download', 'size'),
            download_url: primary.dig('download', 'url'),
            architectures: entries.map { |e| e.dig('channel', 'architecture') }.compact.uniq,
            channels: entries.map { |e| e.dig('channel', 'name') }.compact.uniq,
          }.compact
        }
      end
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      entry = Array(pkg_metadata[:channel_map]).find { |c| c['version'] == version }
      base = entry&.dig('base')
      return [] if base.blank?
      [{
        package_name: base,
        requirements: '*',
        kind: 'runtime',
        ecosystem: 'snap',
      }]
    end

    def maintainers_metadata(name)
      data = fetch_package_metadata(name)
      publisher = data&.dig('snap', 'publisher')
      return [] if publisher.blank? || publisher['username'].blank?
      [{
        uuid: publisher['id'],
        login: publisher['username'],
        name: publisher['display-name'],
        url: maintainer_url_for(publisher['username']),
      }]
    end

    def maintainer_url(maintainer)
      maintainer_url_for(maintainer.login)
    end

    def maintainer_url_for(login)
      "#{@registry_url}/publisher/#{login}"
    end

    def integrity(entry)
      hash = entry&.dig('download', 'sha3-384')
      hash.present? ? "sha3-384-#{hash}" : nil
    end

    def snap_headers
      { 'Snap-Device-Series' => '16' }
    end
  end
end
