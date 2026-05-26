# frozen_string_literal: true

module Ecosystem
  class Freebsd < Base
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
      origin = package.metadata&.dig('origin')

      category, slash, suffix = origin.to_s.partition('/')

      ns = slash.present? ? category.presence : nil
      pname = slash.present? ? suffix : package.name

      qualifiers = {}
      qualifiers['abi'] = package.metadata['abi'] if package.metadata['abi'].present?

      {
        type: 'freebsd',
        namespace: ns,
        name: pname.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
        qualifiers: qualifiers
      }.compact_blank
    end

    def registry_url(package, _version = nil)
      origin = package.metadata&.dig('origin').presence ||
               packages_by_name[package.name]&.dig('origin')

      if origin.blank?
        return "https://ports.freebsd.org/cgi/ports.cgi?query=#{ERB::Util.url_encode(package.name)}&stype=name"
      end

      "https://www.freshports.org/#{origin}/"
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def download_url(package, version)
      return nil unless version.present?

      rec = record_for(package.name, version.number)
      return nil if rec.blank? || rec['repopath'].blank?

      "#{@registry_url.chomp('/')}/#{rec['repopath']}"
    end

    def install_command(package, _version = nil)
      "pkg install #{package.name}"
    end

    def check_status(package)
      return 'removed' if fetch_package_metadata(package.name).blank?
    end

    def packagesite_pkg_url
      "#{@registry_url.chomp('/')}/packagesite.pkg"
    end

    def pkg_cache_slug
      @pkg_cache_slug ||= Digest::MD5.hexdigest(packagesite_pkg_url)[0, 12]
    end

    def packagesite_yaml_path
      yaml_path = Rails.root.join(
        'tmp', 'cache', 'ecosystems',
        "freebsd-packagesite-#{pkg_cache_slug}.extracted.yaml"
      ).to_s

      cached_pkg_path = download_and_cache(
        packagesite_pkg_url,
        "freebsd-packagesite-#{pkg_cache_slug}.pkg",
        ttl: 1.hour
      )

      return nil if cached_pkg_path.blank? || !File.exist?(cached_pkg_path.to_s)

      if !File.exist?(yaml_path) || File.mtime(yaml_path) < File.mtime(cached_pkg_path.to_s)
        Dir.mktmpdir('freebsd-packagesite') do |dir|
          ok = system('tar', '-xf', cached_pkg_path.to_s, '-C', dir, 'packagesite.yaml')
          extracted = File.join(dir, 'packagesite.yaml')

          unless ok && File.exist?(extracted)
            Rails.logger.error("FreeBSD #{registry.name}: failed to extract packagesite.yaml")
            return nil
          end

          FileUtils.cp(extracted, yaml_path)
        end
      end

      yaml_path
    end

    def load_packages_index(yaml_path = packagesite_yaml_path)
      idx = {}

      unless yaml_path.present? && File.exist?(yaml_path)
        Rails.logger.warn("FreeBSD #{registry.name}: no packagesite data at #{yaml_path.inspect}")
        @packages_by_name = idx
        return
      end

      File.foreach(yaml_path) do |line|
        line = line.strip
        next if line.blank?

        begin
          rec = Oj.load(line)
        rescue Oj::ParseError => e
          Rails.logger.warn("FreeBSD packagesite JSON parse error: #{e.message}")
          next
        end

        next unless rec.is_a?(Hash)

        name = rec['name']
        next if name.blank?

        idx[name] = rec
      end

      @packages_by_name = idx
    rescue StandardError => e
      Rails.logger.error("FreeBSD packagesite load error: #{e.message}")
      @packages_by_name = {}
    end

    def packages_by_name
      return @packages_by_name if @packages_by_name

      load_packages_index(packagesite_yaml_path)
      @packages_by_name ||= {}
    end

    def all_package_names
      packages_by_name.keys.sort
    end

    def recently_updated_package_names
      latest_ts_by_name = {}

      packages_by_name.values.each do |rec|
        ts = parse_build_timestamp(rec.dig('annotations', 'build_timestamp'))
        next unless ts && rec['name'].present?

        name = rec['name']
        if latest_ts_by_name[name].nil? || ts > latest_ts_by_name[name]
          latest_ts_by_name[name] = ts
        end
      end

      latest_ts_by_name.sort_by { |_name, timestamp| timestamp }.last(100).reverse.map(&:first)
    end

    def fetch_package_metadata_uncached(name)
      packages_by_name[name]
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank?

      origin = pkg_metadata['origin']
      category = origin.to_s.include?('/') ? origin.to_s.partition('/').first : nil

      {
        name: pkg_metadata['name'],
        description: pkg_metadata['comment'].presence || pkg_metadata['desc'].to_s.truncate(500),
        homepage: pkg_metadata['www'],
        licenses: Array(pkg_metadata['licenses']).presence&.join(', '),
        repository_url: find_repository_url([pkg_metadata['www']]),
        keywords_array: pkg_metadata['categories'] || [],
        namespace: category,
        metadata: {
          origin: origin,
          maintainer: pkg_metadata['maintainer'],
          abi: pkg_metadata['abi'],
          arch: pkg_metadata['arch'],
          categories: pkg_metadata['categories'],
          licenses: pkg_metadata['licenses'],
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      record = fetch_package_metadata(pkg_metadata[:name] || pkg_metadata['name'])
      return [] if record.blank?

      number = record['version']
      return [] if number.blank? || existing_version_numbers.include?(number.to_s)

      [version_hash_for_record(record)]
    end

    def dependencies_metadata(name, version, _pkg_metadata)
      record = fetch_package_metadata(name)
      return [] if record.blank? || record['version'].to_s != version.to_s

      deps = record&.dig('deps')
      return [] if deps.blank? || deps.is_a?(String)

      deps.map do |pkg_name, _meta|
        next if pkg_name.blank?

        {
          package_name: pkg_name,
          requirements: '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase,
        }
      end.compact
    end

    def maintainers_metadata(name)
      record = fetch_package_metadata(name)
      return [] if record.blank?

      parsed_maintainer(record['maintainer'])
    end

    def record_for(pkg_name, version_number)
      record = packages_by_name[pkg_name]
      return nil if record.blank?

      record['version'].to_s == version_number.to_s ? record : nil
    end

    def parse_build_timestamp(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def version_hash_for_record(rec)
      sum = rec['sum']
      h = {
        number: rec['version'],
        published_at: parse_build_timestamp(rec.dig('annotations', 'build_timestamp')),
        integrity: sum.present? ? "sha256-#{sum}" : nil,
        metadata: {
          arch: rec['arch'],
          abi: rec['abi'],
        }.compact
      }
      h.compact
    end

    def parsed_maintainer(raw)
      return [] if raw.blank?

      email = raw.strip
      [{ uuid: email, name: email, email: email }]
    end
  end
end
