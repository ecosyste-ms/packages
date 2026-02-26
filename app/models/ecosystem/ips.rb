# frozen_string_literal: true
module Ecosystem
  class Ips < Base

    def sync_in_batches?
      true
    end

    def sync_maintainers_inline?
      true
    end

    def has_dependent_repos?
      false
    end

    def purl_params(package, version = nil)
      parts = package.name.split('/')
      if parts.length > 1
        namespace = parts[0..-2].join('/')
        name = parts.last
      else
        namespace = nil
        name = parts.first
      end
      {
        type: purl_type,
        namespace: namespace,
        name: name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
      }
    end

    def registry_url(package, version = nil)
      "#{@registry_url}/en/#{package.name}"
    end

    def install_command(package, version = nil)
      "pkg install #{package.name}"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def publisher
      @registry.metadata&.dig('publisher') || 'openindiana.org'
    end

    def catalog_url(part)
      "#{@registry_url}/#{publisher}/catalog/1/#{part}"
    end

    def fetch_catalog(part)
      cache_key = "ips-#{@registry.name}-#{part.gsub('.', '-')}"
      cached_file = download_and_cache(catalog_url(part), cache_key)
      return {} if cached_file.nil?
      Oj.load(File.read(cached_file))
    end

    def base_catalog
      @base_catalog ||= fetch_catalog('catalog.base.C')
    end

    def summary_catalog
      @summary_catalog ||= fetch_catalog('catalog.summary.C')
    end

    def dependency_catalog
      @dependency_catalog ||= fetch_catalog('catalog.dependency.C')
    end

    def base_packages
      @base_packages ||= base_catalog.dig(publisher) || {}
    end

    def summary_packages
      @summary_packages ||= summary_catalog.dig(publisher) || {}
    end

    def dependency_packages
      @dependency_packages ||= dependency_catalog.dig(publisher) || {}
    end

    def parse_actions(actions)
      result = {}
      return result unless actions
      actions.each do |action|
        if action.start_with?('set name=')
          rest = action.sub('set name=', '')
          key, value = rest.split(' value=', 2)
          value = value.gsub(/\A"|"\z/, '') if value
          result[key] = value
        end
      end
      result
    end

    def all_package_names
      base_packages.keys
    end

    def recently_updated_package_names
      names_with_timestamps = base_packages.map do |name, versions|
        latest = versions.last
        timestamp = latest['version'].split(':').last if latest['version']
        [name, timestamp || '']
      end
      names_with_timestamps.sort_by(&:last).last(100).reverse.map(&:first)
    end

    def fetch_package_metadata_uncached(name)
      base = base_packages[name]
      return nil if base.blank?

      summary_versions = summary_packages[name] || []
      latest_summary = summary_versions.last
      summary_actions = parse_actions(latest_summary&.dig('actions'))

      {
        'name' => name,
        'versions' => base,
        'summary' => summary_actions,
        'latest_version_string' => base.last&.dig('version'),
      }
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank?

      summary = pkg_metadata['summary'] || {}
      homepage = summary['info.upstream-url']
      source_url = summary['info.source-url']

      name = pkg_metadata['name']
      parts = name.split('/')
      namespace = parts.length > 1 ? parts.first : nil

      {
        name: name,
        description: summary['pkg.summary'],
        homepage: homepage,
        licenses: nil,
        repository_url: repo_fallback(source_url, homepage),
        namespace: namespace,
        metadata: {
          classification: summary['info.classification'],
          consolidation: summary['org.opensolaris.consolidation'],
          human_version: summary['pkg.human-version'],
        }.compact
      }
    end

    def human_version(version_string)
      return nil if version_string.blank?
      version_string.split(',').first
    end

    def published_at(version_string)
      return nil if version_string.blank?
      timestamp = version_string.split(':').last
      return nil if timestamp.blank?
      Time.parse(timestamp)
    rescue
      nil
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      raw = fetch_package_metadata(pkg_metadata[:name])
      return [] if raw.blank?

      raw['versions'].map do |v|
        version_string = v['version']
        number = human_version(version_string)
        next if number.blank?
        {
          number: number,
          published_at: published_at(version_string),
          integrity: "sha1-#{v['signature-sha-1']}",
          metadata: {
            ips_version: version_string,
          }
        }
      end.compact
    end

    def dependencies_metadata(name, version, pkg_metadata)
      dep_versions = dependency_packages[name]
      return [] if dep_versions.blank?

      raw = fetch_package_metadata(name)
      return [] if raw.blank?

      target_version_string = nil
      if version.present?
        raw['versions'].each do |v|
          if human_version(v['version']) == version
            target_version_string = v['version']
            break
          end
        end
      end

      dep_entry = if target_version_string
        dep_versions.find { |d| d['version'] == target_version_string }
      else
        dep_versions.last
      end
      return [] if dep_entry.blank? || dep_entry['actions'].blank?

      actions = dep_entry['actions']
      obsolete = actions.any? { |a| a.include?('name=pkg.obsolete') && a.include?('value=true') }
      renamed = actions.any? { |a| a.include?('name=pkg.renamed') && a.include?('value=true') }
      return [] if obsolete || renamed

      actions.select { |a| a.start_with?('depend ') && a.include?('type=require') }.filter_map do |action|
        fmri = action[/fmri=(\S+)/, 1]
        next if fmri.blank?
        dep_name = fmri.sub('pkg:/', '').sub('pkg:/', '').split('@').first
        {
          package_name: dep_name,
          requirements: '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end

    def maintainers_metadata(name)
      []
    end
  end
end
