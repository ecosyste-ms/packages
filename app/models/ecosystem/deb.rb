# frozen_string_literal: true
module Ecosystem
  class Deb < Base
    def sync_in_batches?
      true
    end

    def sync_maintainers_inline?
      true
    end

    def has_dependent_repos?
      false
    end

    def version_scheme
      'deb'
    end

    def purl_params(package, version = nil)
      {
        type: version_scheme,
        namespace: purl_namespace,
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
        qualifiers: { 'arch' => 'source', 'distro' => distro_qualifier }
      }
    end

    def registry_url(package, version = nil)
      raise NotImplementedError
    end

    def download_url(package, version)
      return nil unless version.present?
      component = package.metadata['component'] || 'main'
      name = package.name
      prefix = package_pool_prefix(name)
      "#{mirror_url}/pool/#{component}/#{prefix}/#{name}/#{name}_#{version.number}.orig.tar.gz"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def install_command(package, version = nil)
      "apt-get install #{package.name}"
    end

    def fetch_packages_for_component(component)
      codename = registry_codename
      return [] unless codename.present?

      url = "#{mirror_url}/dists/#{codename}/#{component}/source/Sources.gz"
      cache_key = "#{purl_namespace}-#{codename}-#{component}"
      cached_file = download_and_cache(url, cache_key)
      parse_sources(cached_file, component)
    rescue => e
      Rails.logger.error "Error fetching #{purl_namespace} packages for #{component}: #{e.message}"
      []
    end

    def parse_sources(file_path, component)
      return [] if file_path.nil? || !File.exist?(file_path)

      # Stream the Sources.gz file line-by-line to avoid loading
      # multi-gigabyte uncompressed content into memory at once
      results = []
      current_entry = []

      Zlib::GzipReader.open(file_path) do |gz|
        gz.each_line do |line|
          if line.strip.empty?
            unless current_entry.empty?
              entry_text = current_entry.join("\n")
              parsed = parse_source_entry(entry_text, component)
              results << parsed if parsed
              current_entry = []
            end
          else
            current_entry << line.chomp
          end
        end

        # Handle last entry if file doesn't end with blank line
        unless current_entry.empty?
          entry_text = current_entry.join("\n")
          parsed = parse_source_entry(entry_text, component)
          results << parsed if parsed
        end
      end

      results
    end

    def parse_source_entry(entry, component)
      lines = entry.split("\n")
      data = {}
      current_key = nil

      lines.each do |line|
        if line.start_with?(' ')
          next unless current_key && %w[Build-Depends Build-Depends-Indep Build-Depends-Arch].include?(current_key)
          data[current_key] = "#{data[current_key]} #{line.strip}"
        elsif line.include?(': ')
          key, value = line.split(': ', 2)
          current_key = key
          data[key] = value
        end
      end

      return nil if data['Package'].blank?

      {
        name: data['Package'],
        version: data['Version'],
        homepage: data['Homepage'],
        repository_url: data['Vcs-Browser'],
        section: data['Section'],
        metadata: {
          component: component,
          architecture: data['Architecture'],
          priority: data['Priority'],
          binary: data['Binary'],
          standards_version: data['Standards-Version'],
          maintainer: data['Maintainer'],
          build_depends: data['Build-Depends'],
          build_depends_indep: data['Build-Depends-Indep'],
          build_depends_arch: data['Build-Depends-Arch'],
        }
      }
    end

    def packages
      @packages ||= components.flat_map { |c| fetch_packages_for_component(c) }
    end

    def packages_by_name
      @packages_by_name ||= packages.index_by { |p| p[:name] }
    end

    def all_package_names
      packages_by_name.keys
    end

    def recently_updated_package_names
      []
    end

    def fetch_package_metadata_uncached(name)
      packages_by_name[name]
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank? || pkg_metadata[:name].blank?

      {
        name: pkg_metadata[:name],
        homepage: pkg_metadata[:homepage],
        repository_url: repo_fallback(pkg_metadata[:repository_url], pkg_metadata[:homepage]),
        keywords_array: pkg_metadata[:section].present? ? [pkg_metadata[:section]] : [],
        namespace: pkg_metadata.dig(:metadata, :component),
        metadata: (pkg_metadata[:metadata] || {}).merge(homepage_upstream_repository(pkg_metadata[:homepage]))
      }
    end

    # repository_url is the packaging repository (Vcs-Browser), so the upstream project is kept separately in
    # metadata, from debian/upstream/metadata or debian/copyright when they have it and Homepage otherwise
    UPSTREAM_REPOSITORY_KEYS = %w[upstream_repository_url upstream_repository_source upstream_repository_checked].freeze
    PACKAGING_UPSTREAM_SOURCES = %w[debian/upstream/metadata debian/copyright].freeze

    def homepage_upstream_repository(homepage)
      url = UrlParser.try_all(homepage) rescue nil
      url.present? ? { upstream_repository_url: url, upstream_repository_source: 'homepage' } : {}
    end

    # The Sources index doesn't carry the packaging files, so their upstream repository is fetched in the
    # background and kept across syncs until the package has a new version to check
    def merge_existing_metadata(existing, metadata)
      existing = existing.to_h.stringify_keys
      metadata = metadata.to_h.stringify_keys
      metadata['upstream_repository_checked'] = existing['upstream_repository_checked'] if existing['upstream_repository_checked'].present?
      if PACKAGING_UPSTREAM_SOURCES.include?(existing['upstream_repository_source'])
        metadata.merge!(existing.slice('upstream_repository_url', 'upstream_repository_source'))
      end
      metadata
    end

    def after_package_synced(package)
      return if package.latest_release_number.blank?
      return if package.metadata.to_h['upstream_repository_checked'] == package.latest_release_number

      UpdateUpstreamRepositoryWorker.perform_async(package.id)
    end

    def update_upstream_repository(package)
      version = package.latest_release_number
      return if version.blank?

      url, source = packaging_upstream_repository(package, version)
      metadata = package.metadata.to_h.stringify_keys
      if url
        metadata.merge!('upstream_repository_url' => url, 'upstream_repository_source' => source)
      elsif PACKAGING_UPSTREAM_SOURCES.include?(metadata['upstream_repository_source'])
        metadata.merge!(homepage_upstream_repository(package.homepage).stringify_keys.presence || { 'upstream_repository_url' => nil, 'upstream_repository_source' => nil })
      end
      metadata['upstream_repository_checked'] = version
      package.update_columns(metadata: metadata, updated_at: Time.current)
    end

    def packaging_upstream_repository(package, version)
      upstream_metadata = fetch_packaging_file(package, version, 'debian/upstream/metadata')
      url = upstream_metadata_repository(upstream_metadata)
      return [url, 'debian/upstream/metadata'] if url

      url = copyright_source_repository(fetch_packaging_file(package, version, 'debian/copyright'))
      return [url, 'debian/copyright'] if url

      nil
    end

    # A missing file moves on to the next location, any other failure raises so the worker retries
    # instead of marking the version as checked
    def fetch_packaging_file(package, version, path)
      packaging_file_urls(package, version, path).each do |url|
        response = request(url)
        return response.body if response.success? && response.body.present?
        raise PackagingFileError, "#{url} returned HTTP #{response.status}" unless response.success? || response.status == 404
      end
      nil
    end

    class PackagingFileError < StandardError; end

    # salsa.debian.org packaging repositories serve raw files at their default branch. Projects can sit in nested
    # groups (python-team/packages/foo) and Vcs-Browser sometimes points at a page inside the project (/-/tree/...)
    SALSA_PROJECT = %r{\Ahttps://salsa\.debian\.org/[^/]+(?:/[^/]+)+\z}

    def packaging_file_urls(package, version, path)
      repo = package.read_attribute(:repository_url).to_s.sub(%r{/-/.*\z}, '').chomp('/').delete_suffix('.git')
      repo.match?(SALSA_PROJECT) ? ["#{repo}/-/raw/HEAD/#{path}"] : []
    end

    # Repository-Browse is the web page, Repository may be a clone url, UrlParser turns either into the repository url
    def upstream_metadata_repository(body)
      return if body.blank?

      fields = begin
        YAML.safe_load(body)
      rescue Psych::Exception
        nil
      end
      fields = body.scan(/^(Repository(?:-Browse)?):[ \t]*(\S+)/).to_h unless fields.is_a?(Hash)

      fields.values_at('Repository-Browse', 'Repository').each do |value|
        url = repository_from(value)
        return url if url
      end
      nil
    end

    # Only the header paragraph of a machine readable debian/copyright has the Source field
    def copyright_source_repository(body)
      return if body.blank?

      header = body.split(/\n[ \t]*\n/, 2).first.to_s
      source = header.lines.drop_while { |line| !line.start_with?('Source:') }
      return if source.empty?

      field = [source.first.delete_prefix('Source:')] + source.drop(1).take_while { |line| line.start_with?(' ', "\t") }
      field.join(' ').scan(%r{https?://\S+|git://\S+}).each do |value|
        url = repository_from(value)
        return url if url
      end
      nil
    end

    def repository_from(value)
      return unless value.is_a?(String) && value.present?

      UrlParser.try_all(value.strip) rescue nil
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      data = fetch_package_metadata(pkg_metadata[:name])
      return [] if data.blank? || data[:version].blank?
      return [] if existing_version_numbers.include?(data[:version])

      [{
        number: data[:version],
        metadata: {
          architecture: data.dig(:metadata, :architecture)
        }
      }]
    end

    def dependencies_metadata(name, version, pkg_metadata)
      return [] if pkg_metadata.blank?

      deps = []

      if (build_depends = pkg_metadata.dig(:metadata, :build_depends))
        deps += parse_dependencies(build_depends, 'build')
      end

      if (build_depends_indep = pkg_metadata.dig(:metadata, :build_depends_indep))
        deps += parse_dependencies(build_depends_indep, 'build-indep')
      end

      if (build_depends_arch = pkg_metadata.dig(:metadata, :build_depends_arch))
        deps += parse_dependencies(build_depends_arch, 'build-arch')
      end

      deps
    end

    def parse_dependencies(deps_string, kind)
      return [] if deps_string.blank?

      deps_string.split(/,\s*/).map do |dep|
        dep = dep.strip
        dep = dep.gsub(/\s*\[[^\]]*\]\s*/, '').strip
        next if dep.blank?

        if dep =~ /^([^\s(]+)\s*(?:\(([^)]+)\))?/
          dep_name = $1
          requirements = $2 || '*'
        else
          dep_name = dep
          requirements = '*'
        end

        dep_name = dep_name.tr('<>!', '')
        next if dep_name.blank?

        {
          package_name: dep_name,
          requirements: requirements,
          kind: kind,
          ecosystem: self.class.name.demodulize.downcase,
        }
      end.compact
    end

    def maintainers_metadata(name)
      package = fetch_package_metadata(name)
      return [] if package.blank?

      maintainer = package.dig(:metadata, :maintainer)
      return [] if maintainer.blank?

      if maintainer =~ /^(.+?)\s*<(.+?)>/
        name = $1.strip
        email = $2.strip
        [{
          uuid: email,
          name: name,
          email: email
        }]
      else
        []
      end
    end

    # Override these in subclasses

    def mirror_url
      @registry.metadata['mirror'] || @registry.metadata[:mirror] || default_mirror_url
    end

    def default_mirror_url
      raise NotImplementedError
    end

    def components
      raise NotImplementedError
    end

    def purl_namespace
      raise NotImplementedError
    end

    def distro_qualifier
      raise NotImplementedError
    end

    def registry_codename
      @registry.metadata['codename'] || @registry.metadata[:codename]
    end

    def package_pool_prefix(name)
      if name.start_with?('lib') && name.length > 3
        name[0..3]
      else
        name[0]
      end
    end
  end
end
