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

    INSTALL_FLAGS = { 'classic' => ' --classic', 'devmode' => ' --devmode' }.freeze

    def install_command(package, version = nil)
      channel = package.metadata&.dig('channel')
      channel_flag = " --channel=#{channel}" if channel.present?
      "snap install #{package.name}#{channel_flag}#{INSTALL_FLAGS[package.metadata&.dig('confinement')]}"
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

    class RateLimited < StandardError; end

    MAX_SEARCH_PAGES = 200
    SEARCH_PAGE_ATTEMPTS = 3

    def search_index
      return @search_index if @search_index
      # Search returns only strict snaps unless every confinement is asked for.
      url = "#{API_URL}/api/v1/snaps/search?scope=wide&arch=wide&fields=package_name,last_updated&confinement=strict,classic,devmode&size=250&page=1"
      results = []
      MAX_SEARCH_PAGES.times do
        page = search_page(url)
        page.dig('_embedded', 'clickindex:package').each do |e|
          results << { name: e['package_name'], last_updated: e['last_updated'] }
        end
        url = page.dig('_links', 'next', 'href')
        break if url.blank?
      end
      @search_index = results
    end

    def search_page(url)
      attempts = 0
      begin
        page = get_json(url)
        raise "Snap search returned #{page.inspect.truncate(200)}" unless page.is_a?(Hash) && page.dig('_embedded', 'clickindex:package')
        page
      rescue
        attempts += 1
        raise if attempts >= SEARCH_PAGE_ATTEMPTS
        sleep attempts
        retry
      end
    end

    def all_package_names
      search_index.map { |e| e[:name] }
    rescue => e
      Rails.logger.warn("Snap package list unavailable: #{e.message}")
      []
    end

    # The search endpoint has no server-side sort and the newest releases are spread
    # across every page, so this walks the whole index and sorts it here.
    def recently_updated_package_names
      search_index.sort_by { |e| e[:last_updated].to_s }.reverse.first(100).map { |e| e[:name] }
    rescue => e
      Rails.logger.warn("Snap package list unavailable: #{e.message}")
      []
    end

    def sync_recent_packages_incrementally?
      true
    end

    STALE_AFTER = 1.day
    UNTHROTTLED_SYNC_LIMIT = 500

    # last_updated only moves on stable and candidate releases, so whatever budget the
    # recent names leave goes on the packages that have gone longest without a sync.
    def sync_recently_updated_packages_async(period: 15.minutes)
      names = recently_updated_package_names
      spare = (@registry.sync_budget(period) || UNTHROTTLED_SYNC_LIMIT) - names.size
      if spare.positive?
        names += @registry.packages.active.where('last_synced_at < ?', STALE_AFTER.ago)
                          .order(:last_synced_at).limit(spare).pluck(:name)
      end
      @registry.sync_packages_async(names.uniq, period: period, force: true)
    end

    def fetch_package_metadata_uncached(name)
      resp = request("#{API_URL}/v2/snaps/info/#{CGI.escape(name)}?fields=#{FIELDS}", headers: snap_headers.merge('Accept' => 'application/json'))
      raise RateLimited, "Snap Store rate limited the request for #{name}" if resp.status == 429
      data = Oj.load(resp.body)
      return nil if data.nil? || data['error-list'].present? || data['name'].blank?
      data
    rescue RateLimited
      raise
    rescue
      nil
    end

    # A removed snap never gets as far as the status check in a normal sync.
    def handle_missing_package(name)
      @registry.packages.find_by(name: name)&.check_status
      false
    end

    def map_package_metadata(data)
      return false if data.blank? || data['name'].blank?

      snap = data['snap'] || {}
      links = snap['links'] || {}
      publisher = snap['publisher'] || {}
      default = default_entry(data['channel-map'], data['default-track'])

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
          confinement: default&.dig('confinement'),
          channel: install_channel(default, data['default-track']),
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
      package.versions.select(:id, :number, :metadata, :integrity, :status).find_each do |version|
        incoming = remote[version.number]
        if incoming.nil?
          next if version.metadata.blank? || version.metadata['channels'].blank?
          version.update_columns(metadata: version.metadata.merge('channels' => []), updated_at: Time.current)
          next
        end
        # Marking a package removed marks its versions too, and nothing else undoes that.
        version.update_columns(status: nil, updated_at: Time.current) if version.status == 'removed'
        metadata = (version.metadata || {}).merge(incoming[:metadata].stringify_keys)
        next if metadata == version.metadata && incoming[:integrity] == version.integrity
        revision_changed = version.metadata&.dig('revision') != metadata['revision']
        Version.transaction do
          version.update_columns(metadata: metadata, integrity: incoming[:integrity], updated_at: Time.current)
          replace_dependencies(package, version) if revision_changed
        end
      end
    end

    # A version number can be rebuilt as a new revision on a different base.
    def replace_dependencies(package, version)
      deps = dependencies_metadata(package.name, version.number, package_metadata(package.name))
      Dependency.transaction do
        version.dependencies.delete_all
        Dependency.insert_all(deps.map { |dep| dep.merge(version_id: version.id) }) if deps.any?
      end
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      entries = Array(pkg_metadata[:releases]).select { |c| c['version'] == version }
      return [] if entries.empty?
      primary = preferred_entry(entries)
      base = primary['base'] unless primary['base'] == 'none'
      names = [base, *content_default_providers(primary['snap-yaml'])].compact.uniq
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

    RISKS = %w[stable candidate beta edge].freeze

    # The entry a bare `snap install` aims for, or the nearest thing to it.
    def default_entry(channel_map, default_track = nil)
      track = default_track.presence || 'latest'
      entries = Array(channel_map)
      entries = entries.select { |e| e.dig('channel', 'track') == track }.presence || entries
      risk = entries.map { |e| e.dig('channel', 'risk') }.min_by { |r| RISKS.index(r) || RISKS.size }
      preferred_entry(entries.select { |e| e.dig('channel', 'risk') == risk })
    end

    def install_channel(entry, default_track = nil)
      channel = entry&.dig('channel')
      return nil if channel.blank? || channel['risk'].blank?
      track = channel['track'].presence || 'latest'
      return nil if channel['risk'] == 'stable' && track == (default_track.presence || 'latest')
      "#{track}/#{channel['risk']}"
    end

    def content_default_providers(snap_yaml)
      return [] if snap_yaml.blank?
      yaml = YAML.safe_load(snap_yaml) rescue nil
      return [] unless yaml.is_a?(Hash)
      Array(yaml['plugs']).filter_map do |_, plug|
        next unless plug.is_a?(Hash) && plug['interface'] == 'content'
        # Older snaps write the provider as "snap:slot".
        plug['default-provider'].to_s.split(':').first.presence
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
