# frozen_string_literal: true

module Ecosystem
  class Packagist < Base
    CHANGES_STATE_KEY = 'packagist_changes'.freeze
    RECOVERY_BATCH_SIZE = 1_000

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
      raise "Metadata changes returned HTTP #{response.status}" unless response.success?
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
      if %w[delete refresh].include?(action['type'])
        @tagged_response = request("https://repo.packagist.org/p2/#{name}.json")
        if @tagged_response.status == 404
          package = @registry.packages.find_by(name: name)
          package ||= @registry.packages.where('lower(name) = ?', name.downcase).first
          package&.update!(status: 'removed', last_synced_at: Time.current)
          Rails.cache.delete(['packagist', 'enrichment', name])
          Rails.cache.delete(['packagist', 'tagged_versions', name])
          return
        end
        @minimum_metadata_time = action.fetch('time') if action['type'] == 'delete'
      elsif action.fetch('package').end_with?('~dev')
        response = request("https://repo.packagist.org/p2/#{name}~dev.json")
        raise "Development metadata returned HTTP #{response.status}" unless response.success?
        verify_metadata_time(response.headers['last-modified'], action.fetch('time'))
      else
        @minimum_metadata_time = action.fetch('time')
      end
      raise "Failed to sync Packagist package #{name}" unless @registry.sync_package(name, force: true)
    ensure
      @minimum_metadata_time = @tagged_response = nil
    end

    def verify_metadata_time(last_modified, minimum)
      return unless minimum
      raise 'Packagist metadata is older than its change event' unless last_modified.present? && Time.httpdate(last_modified).to_i >= minimum
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
      package = begin
        fetch_package_enrichment(name)
      rescue StandardError => e
        Rails.logger.warn("Failed to fetch Packagist metadata for #{name}: #{e.message}")
        return false
      end
      package.merge('versions' => fetch_tagged_versions(package.fetch('name')))
    end

    def fetch_package_enrichment(name)
      Rails.cache.fetch(['packagist', 'enrichment', name], expires_in: 12.hours) do
        response = request("https://packagist.org/packages/#{name}.json")
        raise "Package metadata returned HTTP #{response.status}" unless response.success?
        data = JSON.parse(response.body).fetch('package')
        data.except('versions').merge('package_version' => data.fetch('versions').values.first)
      end
    end

    def fetch_tagged_versions(name)
      key = ['packagist', 'tagged_versions', name]
      cached = Rails.cache.read(key)
      headers = {}
      headers['If-Modified-Since'] = cached['last_modified'] if cached && cached['last_modified'].present?
      response = @tagged_response || request("https://repo.packagist.org/p2/#{name}.json", headers: headers)
      if response.status == 304 && cached
        verify_metadata_time(cached['last_modified'], @minimum_metadata_time)
        return expand_tagged_versions(cached.fetch('body'), name)
      end
      raise "Tagged metadata returned HTTP #{response.status}" unless response.success?
      verify_metadata_time(response.headers['last-modified'], @minimum_metadata_time)

      versions = expand_tagged_versions(response.body, name)
      Rails.cache.write(key, {'body' => response.body, 'last_modified' => response.headers['last-modified']}, expires_in: 1.day)
      versions
    end

    def expand_tagged_versions(body, name)
      data = JSON.parse(body)
      minified = data['minified']
      raise "Unsupported metadata minification #{minified}" unless minified.nil? || minified == 'composer/2.0'
      entries = data.fetch('packages').fetch(name)
      raise 'Expected a tagged version list' unless entries.is_a?(Array)

      previous = {}
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
        raise 'Missing version number' if number.blank?
        versions[number] = expanded
        previous = expanded
      end
    end

    def check_status(package)
      json = begin
        fetch_package_enrichment(package.name)
      rescue StandardError
        false
      end

      if json.blank? || json == false
        url = check_status_url(package)
        response = Faraday.head(url)
        return "removed" if [302, 404].include?(response.status)
      end

      return "abandoned" if json.is_a?(Hash) && json["abandoned"].present?

      p2_json = get_json("https://repo.packagist.org/p2/#{package.name}~dev.json")
      return "abandoned" if p2_json == "404 not found, no packages here"
      res = p2_json&.dig("packages", package.name)
      return "abandoned" if res == []
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
      latest_version = pkg_metadata['package_version'] || pkg_metadata['versions'].values.first
      return false if latest_version.nil?

      {
        name: pkg_metadata["name"],
        description: pkg_metadata["description"].try(:delete, "\u0000"),
        homepage: latest_version["homepage"],
        keywords_array: Array.wrap(latest_version["keywords"]).reject(&:blank?),
        licenses: Array.wrap(latest_version["license"]).join(","),
        repository_url: repo_fallback(latest_version["source"]&.fetch("url"), latest_version["homepage"]),
        versions: pkg_metadata['versions'],
        downloads: pkg_metadata["downloads"]&.fetch("total"),
        downloads_period: 'total',
        namespace: pkg_metadata["name"].split("/").first,
        metadata: {
          "funding" => latest_version["funding"],
        }
      }
    end

    def update_existing_versions(package, versions_metadata)
      versions_metadata.map { |version| version.fetch(:number) }.each_slice(1_000) do |numbers|
        package.versions.where(number: numbers, status: 'removed').update_all(status: nil, updated_at: Time.current)
      end
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      acceptable_versions(pkg_metadata[:versions]).map do |name, version|
        metadata = {}
        
        metadata[:download_url] = version['dist']['url'] if version['dist']
        
        php_version = extract_php_version(version)
        metadata[:php_version] = php_version if php_version.present?
        
        platform_requirements = extract_platform_requirements(version)
        metadata[:platform_requirements] = platform_requirements if platform_requirements.present?
        
        metadata[:autoload] = version["autoload"] if version["autoload"].present?
        metadata[:extra] = version["extra"] if version["extra"].present?
        metadata[:suggest] = version["suggest"] if version["suggest"].present?
        
        {
          number: version["version"],
          published_at: version["time"],
          integrity: (version['dist'] && version['dist']['shasum'].present?) ? "sha1-#{version['dist']['shasum']}" : nil,
          metadata: metadata
        }
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
