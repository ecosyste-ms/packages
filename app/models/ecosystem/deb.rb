# frozen_string_literal: true
module Ecosystem
  class Deb < Base
    def sync_in_batches?
      true
    end

    def purl_params(package, version = nil)
      {
        type: 'deb',
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
      content = Zlib::GzipReader.open(file_path, &:read)
      entries = content.split("\n\n").reject(&:blank?)

      entries.map do |entry|
        parse_source_entry(entry, component)
      end.compact
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

    def fetch_package_metadata(name)
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
        metadata: pkg_metadata[:metadata]
      }
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
          name: name
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
