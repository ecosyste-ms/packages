# frozen_string_literal: true

module Ecosystem
  class Packagist < Base
    include PackagistMalware

    class RetryableError < RuntimeError; end
    class PackageNotFound < RuntimeError; end

    CHANGES_STATE_KEY = 'packagist_changes'.freeze
    RECOVERY_BATCH_SIZE = 1_000
    VERSION_METADATA_KEYS = %w[download_url published-time source dist php_version platform_requirements autoload extra suggest malware].freeze

    def sync_recent_packages_incrementally?
      true
    end

    def sync_recently_updated_packages_async(period: 15.minutes)
      @registry.with_lock do
        state = @registry.metadata.to_h.fetch(CHANGES_STATE_KEY, {}).dup
        cursor = state['cursor'] || 15.minutes.ago.to_i * 10_000
        data = metadata_changes(cursor)
        actions = data.fetch('actions')

        if actions.any? { |action| action['type'] == 'resync' }
          state['recovery'] = {'phase' => 'known', 'after' => ''}
        end
        enqueue_metadata_actions(actions.reject { |action| action['type'] == 'resync' }, state, period)
        state['cursor'] = data.fetch('timestamp')
        @registry.update!(metadata: @registry.metadata.to_h.merge(CHANGES_STATE_KEY => state))
      end
      recover_metadata_changes(period: period)
    end

    def metadata_changes(cursor)
      response = request("https://packagist.org/metadata/changes.json?since=#{cursor}")
      check_metadata_response(response, 'Metadata changes')
      data = JSON.parse(response.body)
      timestamp = data.fetch('timestamp')
      raise 'Invalid metadata changes cursor' unless timestamp.is_a?(Integer) && timestamp >= cursor
      actions = data.fetch('actions')
      raise 'Expected metadata actions' unless actions.is_a?(Array)
      actions.each { |action| validate_metadata_action(action) }
      data
    end

    def validate_metadata_action(action)
      raise 'Invalid metadata action' unless action.is_a?(Hash) && %w[update delete resync].include?(action['type'])
      raise 'Invalid metadata action time' unless action['time'].is_a?(Integer) && action['time'].positive?
      name = action['package']
      valid_name = name.is_a?(String) && name.match?(%r{\A[a-z0-9_.-]+/[a-z0-9_.-]+(?:~dev)?\z}i)
      valid_name = name == '*' if action['type'] == 'resync'
      raise 'Invalid metadata action package' unless valid_name
    end

    def enqueue_metadata_actions(actions, state, period)
      budget = @registry.sync_budget(period)
      batch_size = budget ? [[budget, 1].max, 1_000].min : 1_000
      next_at = [state['enqueue_at'].to_f, Time.current.to_f].max
      actions.each_slice(batch_size) do |batch|
        jobs = SyncPackagistChangeWorker.set(wait_until: next_at).perform_bulk(batch.map { |action| [@registry.id, action] })
        raise 'Packagist changes were not fully enqueued' unless jobs.size == batch.size && jobs.all?
        next_at += batch.size / @registry.rate_limit.to_f if budget
      end
      state['enqueue_at'] = next_at
    end

    def recover_metadata_changes(period:)
      @registry.with_lock do
        state = @registry.metadata.to_h.fetch(CHANGES_STATE_KEY).deep_dup
        recovery = state['recovery']
        return unless recovery

        limit = RECOVERY_BATCH_SIZE
        if @registry.rate_limit
          next_at = [state['enqueue_at'].to_f, Time.current.to_f].max
          available = ((Time.current.to_f + period.to_f - next_at) * @registry.rate_limit).floor
          limit = [limit, available].min
        end
        return if limit <= 0

        names, next_recovery = metadata_recovery_batch(recovery, limit: limit)
        enqueue_metadata_actions(names.map { |name| {'type' => 'refresh', 'package' => name} }, state, period)
        next_recovery ? state['recovery'] = next_recovery : state.delete('recovery')
        @registry.update!(metadata: @registry.metadata.to_h.merge(CHANGES_STATE_KEY => state))
      end
    end

    def metadata_recovery_batch(recovery, limit:)
      if recovery['phase'] == 'known'
        names = @registry.packages.where('name > ?', recovery['after']).order(:name).limit(limit).pluck(:name)
        next_recovery = if names.size == limit
                          {'phase' => 'known', 'after' => names.last}
                        else
                          {'phase' => 'catalogue', 'after' => ''}
                        end
        return [names, next_recovery]
      end

      response = request('https://packagist.org/packages/list.json')
      raise "Package list returned HTTP #{response.status}" unless response.success?
      catalogue = JSON.parse(response.body).fetch('packageNames')
      raise 'Invalid package list' unless catalogue.is_a?(Array) && catalogue.all? { |name| name.is_a?(String) && name.include?('/') }
      catalogue = catalogue.sort.drop_while { |name| name <= recovery['after'] }
      names = []
      after = recovery['after']
      catalogue.each_slice(1_000) do |batch|
        missing = batch - @registry.packages.where(name: batch).pluck(:name)
        names.concat(missing.first(limit - names.size))
        after = names.size == limit ? names.last : batch.last
        break if names.size == limit
      end
      next_recovery = {'phase' => 'catalogue', 'after' => after} unless catalogue.empty? || after == catalogue.last
      [names, next_recovery]
    end

    def sync_metadata_change(action)
      name = action.fetch('package').delete_suffix('~dev')
      @handling_metadata_change = true
      @package_sync_state = package_sync_state(name)
      if %w[delete refresh].include?(action['type'])
        @tagged_response = request("https://repo.packagist.org/p2/#{name}.json")
        if @tagged_response.status == 404 && action['type'] == 'delete'
          @package_not_found = true
          @deletion_time = action.fetch('time')
          return handle_missing_package(name)
        end
        @minimum_metadata_time = action.fetch('time') if action['type'] == 'delete'
      elsif action.fetch('package').end_with?('~dev')
        response = request("https://repo.packagist.org/p2/#{name}~dev.json")
        check_metadata_response(response, "Development metadata for #{name}")
        verify_metadata_time(response.headers['last-modified'], action.fetch('time'), name: "#{name}~dev")
      else
        @minimum_metadata_time = action.fetch('time')
      end
      result = @registry.sync_package(name, force: true)
      retry_metadata("Failed to sync Packagist package #{name}") unless result || @package_not_found
    ensure
      @minimum_metadata_time = @tagged_response = @handling_metadata_change = @deletion_time = nil
    end

    def verify_metadata_time(last_modified, minimum, name:)
      return unless minimum
      modified = Time.httpdate(last_modified).to_i if last_modified.present?
      retry_metadata("Packagist metadata is older than its change event: #{name}, expected=#{minimum}, last_modified=#{last_modified.inspect}") unless modified && modified >= minimum
    end

    def retry_metadata(message)
      Rails.logger.warn(message)
      raise RetryableError, message
    end

    def check_metadata_response(response, context)
      return if response.success?
      message = "#{context} returned HTTP #{response.status}"
      retry_metadata(message) if [404, 408, 425, 429].include?(response.status) || (500..599).cover?(response.status)
      raise message
    end

    def sync_maintainers_inline?
      true
    end

    def self.purl_type
      "composer"
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: package.name.split('/').first,
        name: package.name.split('/').last,
        version: version.try(:number).try(:encode,'iso-8859-1')
      }
    end


    def registry_url(package, version = nil)
      "#{@registry_url}/packages/#{package.name}##{version}"
    end

    def install_command(package, version = nil)
      "composer require #{package.name}" + (version ? ":#{version}" : "")
    end

    def download_url(_package, version)
      return nil unless version.present?
      version.metadata["download_url"]
    end

    def all_package_names
      get("#{@registry_url}/packages/list.json")["packageNames"]
    rescue
      []
    end

    def recently_updated_package_names
      cursor = @registry.metadata.to_h.dig(CHANGES_STATE_KEY, 'cursor') || 15.minutes.ago.to_i * 10_000
      metadata_changes(cursor).fetch('actions').reject { |action| action['type'] == 'resync' }
        .map { |action| action['package'].delete_suffix('~dev') }.uniq
    end

    def fetch_package_metadata_uncached(name)
      @package_sync_state = package_sync_state(name) unless @handling_metadata_change
      @package_not_found = false
      @enrichment_fetched = false
      package = begin
        fetch_package_enrichment(name)
      rescue PackageNotFound => e
        Rails.logger.warn("Failed to fetch Packagist metadata for #{name}: #{e.message}")
        @package_not_found = true
        return false
      end
      name = package.fetch('name')
      metadata = fetch_tagged_metadata(name)
      if metadata.fetch('versions').empty?
        unless @enrichment_fetched
          Rails.cache.delete(['packagist', 'enrichment', name])
          begin
            package = fetch_package_enrichment(name)
          rescue PackageNotFound
            @package_not_found = true
            return false
          end
        end
        metadata['abandoned'] = abandonment(package)
      else
        metadata['abandoned'] = abandonment(metadata.fetch('versions').values.first)
      end
      constraint = @registry.metadata.to_h.dig(MALWARE_STATE_KEY, 'packages', name.downcase)
      if constraint
        previous = @registry.packages.where(name: name).pick(:metadata)
        previous ||= @registry.packages.where('lower(name) = ?', name.downcase).pick(:metadata)
        metadata['malware'] = complete_malware_flags(metadata.fetch('malware'), constraint, previous.to_h.fetch('malware', []))
      end
      package.merge(metadata, 'packagist_malware_constraint' => constraint)
    end

    def abandonment(metadata)
      value = metadata.fetch('abandoned', false)
      return value if value == true || value == false || (value.is_a?(String) && value.present?)

      raise 'Invalid Packagist abandonment metadata'
    end

    def package_sync_state(name)
      columns = [:id, :updated_at, :last_synced_at, :versions_updated_at, :status, Arel.sql("metadata->>'packagist_snapshot'")]
      @registry.packages.where(name: name).pick(*columns) ||
        @registry.packages.where('lower(name) = ?', name.downcase).pick(*columns)
    end

    def verify_package_sync_state(name)
      return if @package_sync_state == package_sync_state(name)

      @last_fetched_key = @last_fetched_metadata = @tagged_cache_entry = nil
      retry_metadata("Packagist package changed during sync: #{name}")
    end

    def handle_missing_package(name)
      return false unless @package_not_found

      @registry.with_lock do
        verify_package_sync_state(name)
        package = @registry.packages.find_by(name: name)
        package ||= @registry.packages.where('lower(name) = ?', name.downcase).first
        if package
          if @deletion_time && package.metadata.to_h.dig('packagist_snapshot', 'last_modified').to_i > @deletion_time
            retry_metadata("Packagist deletion predates the last applied snapshot: #{name}")
          end
          removed_at = @deletion_time || Time.current.to_i
          removed_at = [removed_at, package.metadata.to_h.fetch('packagist_removed_at', 0)].max
          package.update!(status: 'removed', last_synced_at: Time.current,
            metadata: package.metadata.to_h.merge('packagist_removed_at' => removed_at))
          package.update_details
        end
        [name, package&.name].compact.uniq.each do |cached_name|
          Rails.cache.delete(['packagist', 'enrichment', cached_name])
          Rails.cache.delete(['packagist', 'tagged_versions', cached_name])
        end
        @last_fetched_key = @last_fetched_metadata = @tagged_cache_entry = nil
        @package_sync_state = package_sync_state(name)
        package || false
      end
    end

    def fetch_package_enrichment(name)
      Rails.cache.fetch(['packagist', 'enrichment', name], expires_in: 12.hours) do
        @enrichment_fetched = true
        response = request("https://packagist.org/packages/#{name}.json")
        raise PackageNotFound, "Package metadata for #{name} returned HTTP 404" if response.status == 404
        check_metadata_response(response, "Package metadata for #{name}")
        data = JSON.parse(response.body).fetch('package')
        data.except('versions').merge('package_version' => data.fetch('versions').values.first)
      end
    end

    def fetch_tagged_metadata(name)
      @tagged_cache_entry = nil
      key = ['packagist', 'tagged_versions', name]
      cached = Rails.cache.read(key)
      headers = {}
      headers['If-Modified-Since'] = cached['last_modified'] if cached && cached['last_modified'].present?
      response = @tagged_response || request("https://repo.packagist.org/p2/#{name}.json", headers: headers)
      if response.status == 304 && cached
        verify_metadata_time(cached['last_modified'], @minimum_metadata_time, name: name)
        return tagged_snapshot(cached.fetch('body'), cached['last_modified'], name)
      end
      check_metadata_response(response, "Tagged metadata for #{name}")
      verify_metadata_time(response.headers['last-modified'], @minimum_metadata_time, name: name)

      tagged_snapshot(response.body, response.headers['last-modified'], name)
    end

    def tagged_snapshot(body, last_modified, name)
      metadata = parse_tagged_metadata(body, name)
      snapshot = {'last_modified' => last_modified.present? ? Time.httpdate(last_modified).to_i : nil,
        'sha256' => Digest::SHA256.hexdigest(body)}
      @tagged_cache_entry = {'body' => body, 'last_modified' => last_modified}
      metadata.merge('packagist_snapshot' => snapshot)
    end

    def verify_tagged_snapshot(package_metadata)
      name = package_metadata.fetch(:name)
      snapshot = package_metadata.fetch(:metadata).fetch('packagist_snapshot')
      previous_metadata = @registry.packages.where(name: name).pick(:metadata) ||
        @registry.packages.where('lower(name) = ?', name.downcase).pick(:metadata)
      previous_metadata = previous_metadata.to_h
      previous = previous_metadata['packagist_snapshot']
      invalid = snapshot['last_modified'].nil?
      invalid ||= snapshot['last_modified'].to_i < previous_metadata.fetch('packagist_removed_at', 0)
      if previous && previous['last_modified']
        invalid ||= snapshot['last_modified'].to_i < previous['last_modified'] ||
          (snapshot['last_modified'] == previous['last_modified'] && snapshot['sha256'] != previous['sha256'])
      end
      return unless invalid

      key = ['packagist', 'tagged_versions', name]
      Rails.cache.delete(key) if @tagged_cache_entry && Rails.cache.read(key) == @tagged_cache_entry
      @last_fetched_key = @last_fetched_metadata = @tagged_cache_entry = nil
      retry_metadata("Packagist snapshot is missing a timestamp or conflicts with the last applied snapshot: #{name}")
    end

    def cache_tagged_snapshot(package_metadata)
      return unless @tagged_cache_entry
      Rails.cache.write(['packagist', 'tagged_versions', package_metadata.fetch(:name)], @tagged_cache_entry, expires_in: 1.day)
    end

    def parse_tagged_metadata(body, name)
      data = JSON.parse(body)
      {'versions' => expand_tagged_versions(data, name), 'malware' => malware_flags(data)}
    end

    def expand_tagged_versions(data, name)
      minified = data['minified']
      raise "Unsupported metadata minification #{minified}" unless minified.nil? || minified == 'composer/2.0'
      entries = data.fetch('packages').fetch(name)
      raise 'Expected a tagged version list' unless entries.is_a?(Array)

      previous = {}
      identities = Set.new
      entries.each_with_object({}) do |entry, versions|
        expanded = minified ? previous.dup : {}
        entry.each do |key, value|
          if minified && value == '__unset'
            expanded.delete(key)
          else
            expanded[key] = value
          end
        end
        number = expanded.fetch('version')
        raise 'Invalid version number' unless number.is_a?(String) && number.present?
        raise "Duplicate tagged version #{number}" unless identities.add?(release_key(number))
        versions[number] = expanded
        previous = expanded
      end
    end

    def deprecation_info(name)
      is_deprecated = fetch_package_metadata(name).dig("abandoned") || ""

      {
        is_deprecated: is_deprecated != "",
        message: "",
      }
    end

    def map_package_metadata(pkg_metadata)
      return false unless pkg_metadata
      latest_version = pkg_metadata['package_version'] || pkg_metadata['versions'].values.first || {}

      {
        name: pkg_metadata["name"],
        status: pkg_metadata.fetch('abandoned') == false ? 'active' : 'abandoned',
        description: pkg_metadata["description"].try(:delete, "\u0000"),
        homepage: latest_version["homepage"],
        keywords_array: Array.wrap(latest_version["keywords"]).reject(&:blank?),
        licenses: Array.wrap(latest_version["license"]).join(","),
        repository_url: repo_fallback(latest_version["source"]&.fetch("url"), latest_version["homepage"]),
        versions: pkg_metadata['versions'],
        packagist_malware_constraint: pkg_metadata['packagist_malware_constraint'],
        downloads: pkg_metadata["downloads"]&.fetch("total"),
        downloads_period: 'total',
        namespace: pkg_metadata["name"].split("/").first,
        metadata: {
          "funding" => latest_version["funding"],
          "abandoned" => pkg_metadata.fetch('abandoned'),
          "malware" => pkg_metadata.fetch('malware', []),
          "packagist_snapshot" => pkg_metadata.fetch('packagist_snapshot'),
        }
      }
    end

    def update_existing_versions(package, versions_metadata)
      incoming = versions_metadata.index_by { |version| release_key(version.fetch(:number)) }
      package.versions.find_each do |version|
        attributes = incoming[release_key(version.number)]
        if attributes
          attributes = attributes.except(:number, :status)
          metadata = attributes.fetch(:metadata).stringify_keys
          if attributes[:integrity].nil? && version.metadata.to_h['download_url'] == metadata['download_url']
            attributes = attributes.except(:integrity)
          end
          version.assign_attributes(attributes.merge(metadata: merge_version_metadata(version.metadata, metadata)))
          version.status = nil if version.status == 'removed'
        elsif version.status.nil? || version.status == 'malware'
          version.status = 'removed'
        end
        version.update_columns(version.changes.transform_values(&:last).merge(updated_at: Time.current)) if version.changed?
      end
      apply_malware_flags(package, package.metadata.fetch('malware', []), versions_metadata.map { |v| v.fetch(:number) })
    end

    def release_key(number)
      number.sub(/\Av(?=\d)/i, '').downcase
    end

    def merge_version_metadata(existing_metadata, new_metadata)
      existing_metadata.to_h.except(*VERSION_METADATA_KEYS).merge(new_metadata.stringify_keys)
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      ranges = malware_ranges(pkg_metadata.fetch(:metadata, {}).fetch('malware', []))
      existing = existing_version_numbers.group_by { |number| release_key(number) }
      acceptable_versions(pkg_metadata[:versions]).map do |name, version|
        aliases = existing[release_key(version.fetch('version'))] || []
        number = aliases.include?(version['version']) ? version['version'] : aliases.first || version['version']
        metadata = {}
        matches = matching_malware_flags(ranges, version.fetch('version'))
        metadata[:malware] = matches if matches.any?
        
        metadata['published-time'] = version['published-time'] if version['published-time'].present?
        metadata[:source] = version['source'].slice('type', 'url', 'reference') if version['source'].present?
        metadata[:dist] = version['dist'].slice('type', 'url', 'reference') if version['dist'].present?
        metadata[:download_url] = version['dist']['url'] if version['dist']
        
        php_version = extract_php_version(version)
        metadata[:php_version] = php_version if php_version.present?
        
        platform_requirements = extract_platform_requirements(version)
        metadata[:platform_requirements] = platform_requirements if platform_requirements.present?
        
        metadata[:autoload] = version["autoload"] if version["autoload"].present?
        metadata[:extra] = version["extra"] if version["extra"].present?
        metadata[:suggest] = version["suggest"] if version["suggest"].present?
        
        {
          number: number,
          registry_id: @registry.id,
          published_at: version["time"],
          licenses: Array.wrap(version["license"]).join(","),
          integrity: (version['dist'] && version['dist']['shasum'].present?) ? "sha1-#{version['dist']['shasum']}" : nil,
          metadata: metadata
        }.merge(status: matches.any? && aliases.empty? ? 'malware' : nil)
      end
    end

    def acceptable_versions(versions)
      versions.select do |_n, k|
        # See: https://getcomposer.org/doc/articles/versions.md#branches
        (k['version'] =~ /^dev-.*/i).nil? && (k['version'] =~ /\.x-dev$/i).nil?
      end
    end

    def dependencies_metadata(_name, version, package)
      vers = package[:versions][version]
      vers ||= package[:versions].values.find { |entry| release_key(entry.fetch('version')) == release_key(version) }
      return [] if vers.nil?

      map_dependencies(vers.fetch("require", {}).reject { |k, _v| k == "php" }, "runtime") +
        map_dependencies(vers.fetch("require-dev", {}).reject { |k, _v| k == "php" }, "Development")
    end

    def maintainers_metadata(name)
      json = fetch_package_enrichment(name)
      json['maintainers'].map do |user|
        {
          uuid: user["name"],
          login: user["name"],
        }
      end
    rescue StandardError
      []
    end

    def maintainer_url(maintainer)
      "https://packagist.org/users/#{maintainer.login}"
    end

    private

    def extract_php_version(version)
      require_section = version["require"] || {}
      require_section["php"]
    end

    def extract_platform_requirements(version)
      require_section = version["require"] || {}
      platform_reqs = require_section.select do |package, _constraint|
        package.start_with?("ext-") || package.start_with?("lib-") || package == "php-64bit" || package == "php-zts"
      end
      
      platform_reqs.empty? ? nil : platform_reqs
    end
  end
end
