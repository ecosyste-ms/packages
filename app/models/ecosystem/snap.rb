# frozen_string_literal: true

module Ecosystem
  class Snap < Base
    API_URL = 'https://api.snapcraft.io'
    FIELDS = %w[
      title summary description license contact website publisher categories links
      store-url snap-id revision version download created-at base confinement type snap-yaml
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
      return 'removed' if [400, 404, 410].include?(resp.status)
      resp.success? ? nil : false
    rescue
      false
    end

    RECENT_PAGE_LIMIT = 4

    # The search endpoint has no server-side sort, so recent-update detection reads the
    # first RECENT_PAGE_LIMIT pages (popularity order) rather than the full ~45-page index.
    def search_index(max_pages: nil)
      return @search_index if @search_index
      url = "#{API_URL}/api/v1/snaps/search?scope=wide&arch=wide&fields=package_name,last_updated&size=250&page=1"
      results = []
      (max_pages || 200).times do
        page = get_json(url)
        raise "Snap search returned #{page.inspect.truncate(200)}" unless page.is_a?(Hash) && page.dig('_embedded', 'clickindex:package')
        page.dig('_embedded', 'clickindex:package').each do |e|
          results << { name: e['package_name'], last_updated: e['last_updated'] }
        end
        url = page.dig('_links', 'next', 'href')
        break if url.blank?
      end
      @search_index = results if max_pages.nil?
      results
    end

    def all_package_names
      search_index.map { |e| e[:name] }
    rescue => e
      Rails.logger.warn("Snap package list unavailable: #{e.message}")
      []
    end

    def recently_updated_package_names
      search_index(max_pages: RECENT_PAGE_LIMIT).sort_by { |e| e[:last_updated].to_s }.reverse.first(100).map { |e| e[:name] }
    rescue => e
      Rails.logger.warn("Snap package list unavailable: #{e.message}")
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
        releases: data['channel-map'],
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
      grouped = Array(pkg_metadata[:releases]).group_by { |c| c['version'] }
      grouped.filter_map do |version, entries|
        next if version.blank?
        primary = preferred_entry(entries)
        {
          number: version,
          published_at: entries.map { |e| e['created-at'] }.compact.min,
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

    # Channels move as revisions are promoted, so refresh what was recorded on first sync.
    def update_existing_versions(package, versions_metadata)
      remote = versions_metadata.index_by { |v| v[:number] }
      package.versions.select(:id, :number, :metadata, :integrity).find_each do |version|
        incoming = remote[version.number]
        if incoming.nil?
          next if version.metadata.blank? || version.metadata['channels'].blank?
          version.update_columns(metadata: version.metadata.merge('channels' => []), updated_at: Time.current)
          next
        end
        metadata = (version.metadata || {}).merge(incoming[:metadata].stringify_keys)
        next if metadata == version.metadata && incoming[:integrity] == version.integrity
        version.update_columns(metadata: metadata, integrity: incoming[:integrity], updated_at: Time.current)
      end
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      entries = Array(pkg_metadata[:releases]).select { |c| c['version'] == version }
      return [] if entries.empty?
      primary = preferred_entry(entries)
      names = [primary['base'], *content_default_providers(primary['snap-yaml'])].compact.uniq
      names.map do |dep|
        { package_name: dep, requirements: '*', kind: 'runtime', ecosystem: 'snap' }
      end
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

    def preferred_entry(entries)
      entries.find { |e| e.dig('channel', 'architecture') == 'amd64' } || entries.first
    end

    def content_default_providers(snap_yaml)
      return [] if snap_yaml.blank?
      yaml = YAML.safe_load(snap_yaml) rescue nil
      return [] unless yaml.is_a?(Hash)
      Array(yaml['plugs']).filter_map do |_, plug|
        next unless plug.is_a?(Hash) && plug['interface'] == 'content'
        plug['default-provider'].presence
      end
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
