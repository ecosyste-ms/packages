# frozen_string_literal: true

module Ecosystem
  class Opam < Base
    API_URL = 'https://ocaml.org/graphql'.freeze
    ARCHIVE_URL = 'https://github.com/ocaml/opam-repository-archive'.freeze
    ARCHIVE_INDEX_URL = 'https://api.github.com/repos/ocaml/opam-repository-archive/git/trees/main?recursive=1'.freeze
    ARCHIVE_RAW_URL = 'https://raw.githubusercontent.com/ocaml/opam-repository-archive/main'.freeze
    class PackageNotFound < RuntimeError; end
    PAGE_SIZE = 500
    VERSION_FIELDS = <<~GRAPHQL.freeze
      name version license publication
      url { uri checksum }
    GRAPHQL
    VERSION_METADATA_KEYS = %w[archived archive_reason archive_commit download_url checksums dependency_formulas conflicts available depexts].freeze

    def registry_url(package, version = nil)
      if version && archived_version?(package, version)
        return "#{ARCHIVE_URL}/blob/main/packages/#{package.name}/#{package.name}.#{version}/opam"
      end
      return "#{ARCHIVE_URL}/tree/main/packages/#{package.name}" if version.nil? && package.metadata&.dig('archived')
      path = "#{@registry_url}/packages/#{package.name}/"
      version ? "#{path}#{package.name}.#{version}/" : path
    end

    def documentation_url(package, version = nil)
      return nil if archived_version?(package, version)
      "https://ocaml.org/p/#{package.name}/#{version || 'latest'}/doc/index.html"
    end

    def install_command(package, version = nil)
      command = "opam install #{package.name}#{".#{version}" if version}"
      archived_version?(package, version) ? "opam repository add archive git+#{ARCHIVE_URL} && #{command}" : command
    end

    def archived_version?(package, version)
      return package.metadata&.dig('archived') == true unless version
      record = version.respond_to?(:opam_archived?) ? version : package.versions.find_by(number: version.to_s)
      record&.opam_archived?
    end

    def download_url(_package, version = nil)
      version&.metadata&.dig('download_url')
    end

    def check_status(package)
      graphql('query($name: String!) { package(name: $name) { name } }', name: package.name).fetch('package').present? ? nil : false
    rescue PackageNotFound
      archive_index.key?(package.name) ? nil : false
    rescue Faraday::Error, RuntimeError
      false
    end

    def package_index
      entries = []
      loop do
        data = graphql(<<~GRAPHQL, limit: PAGE_SIZE, offset: entries.length).fetch('allPackages')
          query($limit: Int!, $offset: Int!) {
            allPackages(limit: $limit, offset: $offset) {
              totalPackages packages { name publication }
            }
          }
        GRAPHQL
        page = data.fetch('packages')
        break if page.empty?
        entries.concat(page)
        break if entries.length >= data.fetch('totalPackages')
      end
      entries
    end

    def all_package_names
      (package_index.map { |package| package.fetch('name') } + archive_index.keys).uniq
    end

    def recently_updated_package_names
      recent = package_index.sort_by { |package| package['publication'].to_f }.reverse.first(100).map { |package| package.fetch('name') }
      # The archive has no update timestamps, so revisit its packages too.
      (recent + archive_index.keys).uniq
    end

    def archive_index
      @archive_index ||= Rails.cache.fetch('opam/archive-index/v1', expires_in: 1.hour) do
        response = request(ARCHIVE_INDEX_URL)
        raise "Opam archive index unavailable (HTTP #{response.status})" unless response.success?
        data = JSON.parse(response.body)
        raise 'Opam archive index is truncated' if data['truncated']
        data.fetch('tree').each_with_object({}) do |entry, index|
          match = entry['path'].match(%r{\Apackages/([^/]+)/\1\.([^/]+)/opam\z})
          next unless entry['type'] == 'blob' && match
          (index[match[1]] ||= []) << match[2]
        end
      end
    end

    def fetch_package_metadata_uncached(name)
      archived_numbers = archive_index.fetch(name, [])
      begin
        data = graphql(<<~GRAPHQL, name: name)
          query($name: String!) {
            package(name: $name) {
              #{VERSION_FIELDS}
              synopsis description homepage tags authors maintainers
            }
            packgeByVersions(name: $name) { packages { #{VERSION_FIELDS} } }
          }
        GRAPHQL
      rescue PackageNotFound
        raise if archived_numbers.empty?
        data = { 'packgeByVersions' => { 'packages' => [] } }
      end

      versions = data.fetch('packgeByVersions').fetch('packages')
      versions.each do |version|
        begin
          version['manifest'] = fetch_manifest(name, version.fetch('version'))
          version['archived'] = false
        rescue PackageNotFound
          manifest = fetch_manifest(name, version.fetch('version'), archived: true)
          version.merge!(archived_package(name, version.fetch('version'), manifest))
        end
      end
      (archived_numbers - versions.map { |version| version['version'] }).each do |number|
        manifest = fetch_manifest(name, number, archived: true)
        versions << archived_package(name, number, manifest)
      end

      latest = data['package']
      if latest && (release = versions.find { |version| version['version'] == latest['version'] }) && !release['archived']
        latest['manifest'] = release.fetch('manifest')
      else
        candidates = versions.reject { |version| version['archived'] }
        release = (candidates.presence || versions).max { |left, right| self.class.compare_versions(left['version'], right['version']) }
        data['package'] = archived_package(name, release.fetch('version'), release.fetch('manifest'))
      end
      data['archived'] = versions.all? { |version| version['archived'] }
      data
    end

    def archived_package(name, number, manifest)
      source = manifest.section('url')
      {
        'name' => name, 'version' => number, 'manifest' => manifest, 'archived' => true,
        'synopsis' => manifest.strings('synopsis').first,
        'description' => manifest.strings('description').first,
        'homepage' => manifest.strings('homepage'),
        'license' => manifest.strings('license').join(' AND '),
        'tags' => manifest.strings('tags'),
        'authors' => manifest.strings('authors'),
        'maintainers' => manifest.strings('maintainer'),
        'url' => { 'uri' => source&.strings('src')&.first, 'checksum' => source&.strings('checksum') }
      }
    end

    def fetch_manifest(name, version, archived: false)
      root = archived ? ARCHIVE_RAW_URL : @registry_url
      url = "#{root}/packages/#{name}/#{name}.#{version}/opam"
      response = request(url)
      raise PackageNotFound, "Opam manifest not found: #{name}.#{version}" if [404, 410].include?(response.status)
      raise "Opam manifest unavailable: #{name}.#{version} (HTTP #{response.status})" unless response.success?
      manifest = OpamManifest.new(response.body)
      raise ArgumentError, 'Missing opam-version field' if manifest.strings('opam-version').empty?
      manifest.formula('depends')
      manifest.formula('depopts')
      manifest
    end

    def map_package_metadata(data)
      package = data.fetch('package')
      manifest = package.fetch('manifest')
      {
        name: package.fetch('name'),
        description: package['synopsis'].presence || package['description'],
        homepage: Array(package['homepage']).first,
        repository_url: repo_fallback(manifest.strings('dev-repo').first, Array(package['homepage']).first),
        licenses: package['license'],
        keywords_array: package['tags'],
        versions: data.fetch('packgeByVersions').fetch('packages'),
        metadata: {
          archived: data.fetch('archived'),
          description: package['description'],
          authors: package['authors'],
          maintainers: package['maintainers'],
        }.compact
      }
    end

    def versions_metadata(package, _existing_version_numbers = [])
      package.fetch(:versions).map do |version|
        manifest = version.fetch('manifest')
        {
          number: version.fetch('version'),
          published_at: (Time.at(version['publication']).utc if version['publication'].to_f.positive?),
          licenses: version['license'],
          metadata: {
            archived: version.fetch('archived'),
            archive_reason: (manifest.strings('x-reason-for-archiving') + manifest.strings('x-reason-for-archival') if version['archived']),
            archive_commit: ((manifest.strings('x-opam-repository-commit-hash-at-time-of-archiving') + manifest.strings('x-opam-repository-commit-hash-at-time-of-archival')).first if version['archived']),
            download_url: version.dig('url', 'uri'),
            checksums: version.dig('url', 'checksum'),
            dependency_formulas: { depends: manifest.formula('depends'), depopts: manifest.formula('depopts') }.compact,
            conflicts: manifest.raw('conflicts'),
            available: manifest.raw('available'),
            depexts: manifest.raw('depexts'),
          }.compact
        }
      end
    end

    def merge_version_metadata(existing_metadata, new_metadata)
      (existing_metadata || {}).except(*VERSION_METADATA_KEYS).merge(new_metadata.stringify_keys)
    end

    def update_existing_versions(package, versions_metadata)
      incoming = versions_metadata.index_by { |version| version[:number] }
      package.versions.where(number: incoming.keys).find_each do |version|
        metadata = merge_version_metadata(version.metadata, incoming.fetch(version.number).fetch(:metadata))
        next if metadata == version.metadata
        changed_dependencies = version.metadata&.dig('dependency_formulas') != metadata['dependency_formulas']
        version.transaction do
          version.update_columns(metadata: metadata, updated_at: Time.current)
          if changed_dependencies
            data = fetch_package_metadata(package.name)
            dependencies = dependencies_metadata(package.name, version.number, versions: data.fetch('packgeByVersions').fetch('packages'))
            version.dependencies.delete_all
            version.dependencies.insert_all(dependencies) if dependencies.any?
          end
        end
      end
    end

    def dependencies_metadata(_name, number, package)
      version = package.fetch(:versions).find { |entry| entry['version'] == number }
      return [] unless version

      manifest = version.fetch('manifest')
      (manifest.dependencies('depends') + manifest.dependencies('depopts', optional: true)).map do |dependency|
        {
          package_name: dependency.fetch(:name),
          requirements: dependency[:constraints].presence || '*',
          kind: dependency_kind(dependency[:constraints]),
          optional: dependency[:optional],
          ecosystem: 'opam',
        }
      end
    end

    def dependency_kind(constraints)
      return 'runtime' if constraints.to_s.include?('|')
      case constraints.to_s
      when /\Awith-test(?:\s*&|\z)/ then 'test'
      when /\Awith-doc(?:\s*&|\z)/ then 'documentation'
      when /\A(?:with-dev-setup|dev)(?:\s*&|\z)/ then 'development'
      when /\Abuild(?:\s*&|\z)/ then 'build'
      else 'runtime'
      end
    end

    def graphql(query, variables = {})
      connection = Faraday.new(API_URL, headers: { 'User-Agent' => 'packages.ecosyste.ms', 'Content-Type' => 'application/json' }) do |builder|
        builder.request :instrumentation
        builder.response :raise_error
        builder.adapter Faraday.default_adapter
        builder.options.timeout = 30
        builder.options.open_timeout = 5
      end
      response = connection.post { |request| request.body = { query: query, variables: variables }.to_json }
      result = JSON.parse(response.body)
      if result['errors'].present? && result['errors'].all? { |error| error['message'] == "No package matching #{variables[:name]} was found" }
        raise PackageNotFound, "Opam package not found: #{variables[:name]}"
      end
      raise "Opam GraphQL: #{result['errors'].map { |error| error['message'] }.join('; ')}" if result['errors'].present?
      result.fetch('data')
    end

    def self.compare_versions(left, right)
      left = left.dup
      right = right.dup
      until left.empty? && right.empty?
        while left.match?(/\A[^0-9]/) || right.match?(/\A[^0-9]/)
          comparison = character_order(left[0]) <=> character_order(right[0])
          return comparison unless comparison.zero?
          left = left[1..] || ''
          right = right[1..] || ''
        end
        left_digits = left[/\A[0-9]*/]
        right_digits = right[/\A[0-9]*/]
        comparison = left_digits.to_i <=> right_digits.to_i
        return comparison unless comparison.zero?
        left = left.delete_prefix(left_digits)
        right = right.delete_prefix(right_digits)
      end
      0
    end

    def self.character_order(character)
      return -1 if character == '~'
      return 0 if character.nil? || character.match?(/[0-9]/)
      character.match?(/[a-zA-Z]/) ? character.ord : character.ord + 256
    end
  end
end
