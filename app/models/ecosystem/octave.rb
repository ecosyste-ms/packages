# frozen_string_literal: true

module Ecosystem
  class Octave < Base
    INDEX_CACHE_KEY = 'octave/packages-index/v1'
    RELEASE_KEYS = %w[id date sha256 url depends].freeze
    DEPENDENCY_PATTERN = /\A\s*([^\s(]+)\s*(?:\(\s*(.*?)\s*\))?\s*\z/
    INTERPRETER = 'octave'
    ARCHIVE_PATTERN = /\.(?:tar\.gz|tgz|tar\.bz2|tar\.xz|zip)\z/i

    def sync_maintainers_inline?
      true
    end

    def registry_url(package, _version = nil)
      "#{@registry_url}/#{package.name}"
    end

    def download_url(_package, version = nil)
      version&.metadata&.dig('download_url')
    end

    def install_command(package, version = nil)
      url = download_url(package, version || package.latest_version)
      return nil unless url.to_s.match?(ARCHIVE_PATTERN)
      "pkg install \"#{url}\""
    end

    def check_status(package)
      package_index.key?(package.name) ? nil : 'removed'
    rescue StandardError => e
      Rails.logger.warn("Error checking status for Octave package #{package.name}: #{e.message}")
      false
    end

    # The index sends ETag and Last-Modified, so repeat syncs reuse the cached body on a 304
    def package_index
      @package_index ||= begin
        cached = Rails.cache.read(INDEX_CACHE_KEY)
        headers = { 'Accept' => 'application/json' }
        headers['If-None-Match'] = cached[:etag] if cached&.dig(:etag)
        headers['If-Modified-Since'] = cached[:last_modified] if cached&.dig(:last_modified)
        response = request("#{@registry_url}/packages.json", headers: headers)

        body = if response.status == 304 && cached
                 cached[:body]
               elsif response.success?
                 Rails.cache.write(INDEX_CACHE_KEY, { etag: response.headers['etag'], last_modified: response.headers['last-modified'], body: response.body })
                 response.body
               else
                 raise "Octave package index unavailable (HTTP #{response.status})"
               end
        index = Oj.load(body)
        raise 'Octave package index is not a JSON object' unless index.is_a?(Hash)
        index
      end
    end

    def all_package_names
      package_index.keys
    rescue StandardError
      []
    end

    def recently_updated_package_names
      package_index.map { |name, pkg| [name, releases(pkg).map { |release| release['date'].to_s }.max.to_s] }
        .sort_by { |_name, date| date }.reverse.first(100).map(&:first)
    rescue StandardError
      []
    end

    def fetch_package_metadata_uncached(name)
      package_index[name]
    end

    def map_package_metadata(pkg)
      return false if pkg.blank? || pkg['name'].blank?

      links = Array(pkg['links'])
      homepage = link_url(links, 'package documentation') || link_url(links, 'function reference')
      {
        name: pkg['name'],
        description: pkg['description'],
        homepage: homepage,
        licenses: links.find { |link| link['icon'].to_s.include?('fa-copyright') }&.dig('label'),
        repository_url: repo_fallback(link_url(links, 'repository'), homepage),
        versions: releases(pkg),
        metadata: {
          icon: pkg['icon'].presence,
          maintainers: pkg['maintainers'].presence,
          news_url: link_url(links, 'news'),
          issues_url: link_url(links, 'report a problem'),
          function_reference_url: link_url(links, 'function reference'),
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      Array(pkg_metadata[:versions]).map do |release|
        dependencies = parse_dependencies(release['depends'])
        sha256 = release['sha256'].presence
        {
          number: release['id'],
          published_at: release['date'].presence,
          integrity: (sha256 ? "sha256-#{sha256.downcase}" : nil),
          metadata: {
            download_url: release['url'].presence,
            octave_requirements: dependencies[:interpreter].presence,
            system_requirements: release.except(*RELEASE_KEYS).presence,
          }.compact
        }
      end
    end

    def dependencies_metadata(_name, version, pkg_metadata)
      release = Array(pkg_metadata[:versions]).find { |entry| entry['id'] == version }
      return [] unless release

      parse_dependencies(release['depends'])[:packages].map do |package_name, requirements|
        {
          package_name: package_name,
          requirements: requirements.presence&.join(', ') || '*',
          kind: 'runtime',
          ecosystem: self.class.name.demodulize.downcase
        }
      end
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] unless pkg

      Array(pkg['maintainers']).filter_map do |maintainer|
        contact = maintainer['contact'].to_s.strip
        uuid = contact.presence || maintainer['name'].to_s.strip
        next if uuid.blank?
        {
          uuid: uuid,
          name: maintainer['name'].presence,
          email: (contact if contact.match?(URI::MailTo::EMAIL_REGEXP)),
          url: (contact if contact.match?(%r{\Ahttps?://}i)),
        }
      end
    end

    # Releases only; "dev" entries point at moving branch archives rather than published versions
    def releases(pkg)
      Array(pkg['versions']).select { |release| release['id'].present? && release['id'] != 'dev' }
    end

    def parse_dependencies(depends)
      result = { interpreter: [], packages: {} }
      Array(depends).each do |dependency|
        match = DEPENDENCY_PATTERN.match(dependency.to_s)
        next unless match
        name, requirement = match[1], match[2].presence
        if name == INTERPRETER
          result[:interpreter] << requirement if requirement
        else
          (result[:packages][name] ||= []) << requirement
          result[:packages][name].compact!
        end
      end
      result
    end

    private

    def link_url(links, label)
      links.find { |link| link['label'].to_s.casecmp?(label) }&.dig('url').presence
    end
  end
end
