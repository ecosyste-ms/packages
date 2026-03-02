# frozen_string_literal: true

module Ecosystem
  class Guix < Base
    def self.purl_type
      'guix'
    end

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def registry_url(package, version = nil)
      v = version.is_a?(String) ? version : version.try(:number)
      v ||= package.versions.first.try(:number)
      "https://packages.guix.gnu.org/packages/#{package.name}/#{v}/"
    end

    def install_command(package, version = nil)
      v = version.is_a?(String) ? version : version.try(:number)
      if v.present?
        "guix install #{package.name}@#{v}"
      else
        "guix install #{package.name}"
      end
    end

    def documentation_url(package, _version = nil)
      location = package.metadata&.dig('location')
      return nil unless location.present?

      file_path, line = location.split(':')
      "https://git.savannah.gnu.org/cgit/guix.git/tree/#{file_path}#n#{line}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return 'removed' if pkg.blank?
      nil
    end

    def packages_url
      "https://guix.gnu.org/packages.json"
    end

    def packages
      @@guix_packages_cache ||= load_packages_json
    end

    def self.clear_packages_cache!
      @@guix_packages_cache = nil
    end

    def load_packages_json
      response = get_raw(packages_url)
      raw = Oj.load(response)

      return {} if raw.nil? || !raw.is_a?(Array)

      index = {}
      raw.each do |entry|
        name = entry['name']
        next if name.blank?
        index[name] ||= []
        index[name] << entry
      end
      index
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      url = "https://git.savannah.gnu.org/cgit/guix.git/atom/?h=master"
      begin
        feed = SimpleRSS.parse(get_raw(url))
        feed.items.flat_map do |item|
          title = item.title.to_s
          if title.include?(':')
            [title.split(':').first.strip]
          else
            []
          end
        end.uniq.first(100)
      rescue
        []
      end
    end

    def fetch_package_metadata_uncached(name)
      packages[name]
    end

    def package_metadata(name)
      entries = fetch_package_metadata(name)
      map_package_metadata(entries, name)
    end

    def map_package_metadata(entries, name = nil)
      return false if entries.blank?

      entries = entries.is_a?(Array) ? entries : [entries]
      latest = entries.max_by { |e| e['version'].to_s }
      return false if latest.blank?

      name ||= latest['name']

      licenses = parse_license_from_location(latest['location'])

      {
        name: name,
        description: latest['synopsis'],
        homepage: latest['homepage'],
        licenses: licenses,
        repository_url: repo_fallback('', latest['homepage']),
        metadata: {
          location: latest['location'],
          variable_name: latest['variable_name'],
        }.compact
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      entries = fetch_package_metadata(pkg_metadata[:name])
      return [] if entries.blank?

      Array(entries).map do |entry|
        integrity = entry.dig('source', 0, 'integrity')

        {
          number: entry['version'],
          integrity: integrity,
          metadata: {
            variable_name: entry['variable_name'],
          }.compact
        }
      end
    end

    def maintainers_metadata(_name)
      []
    end

    def dependencies_metadata(name, _version, _package)
      entries = fetch_package_metadata(name)
      return [] if entries.blank?

      entries = entries.is_a?(Array) ? entries : [entries]
      latest = entries.max_by { |e| e['version'].to_s }
      return [] if latest.blank?

      location = latest['location']
      return [] if location.blank?

      content = fetch_scheme_file(location)
      return [] if content.blank?

      line_number = location.split(':').last.to_i
      block = find_package_block(content, line_number)
      return [] if block.blank?

      parse_guix_dependencies(block)
    rescue => e
      Rails.logger.warn "[Guix] Failed to fetch dependencies for #{name}: #{e.message}"
      []
    end

    def fetch_scheme_file(location)
      file_path = location.split(':').first
      url = "https://raw.githubusercontent.com/Millak/guix/master/#{file_path}"
      response = get_raw(url)
      response.presence
    rescue
      nil
    end

    def find_package_block(content, line_number)
      lines = content.lines
      return nil if line_number < 1 || line_number > lines.length

      # Search backwards from the given line to find (define-public
      start_line = nil
      (line_number - 1).downto(0) do |i|
        if lines[i] =~ /\(define-public\s/
          start_line = i
          break
        end
      end

      return nil unless start_line

      # Track balanced parens from start_line to find the end
      depth = 0
      end_line = nil
      (start_line...lines.length).each do |i|
        lines[i].each_char do |c|
          depth += 1 if c == '('
          depth -= 1 if c == ')'
        end
        if depth == 0
          end_line = i
          break
        end
      end

      return nil unless end_line

      lines[start_line..end_line].join
    end

    def strip_scheme_comments(content)
      return '' if content.blank?
      content.gsub(/;[^\n]*/, '')
    end

    def parse_guix_license(block)
      return nil if block.blank?
      block = strip_scheme_comments(block)

      # Find the (license ...) form
      idx = block.index('(license ')
      return nil unless idx

      # Extract the balanced s-expression starting at (license
      depth = 0
      end_idx = nil
      (idx...block.length).each do |i|
        depth += 1 if block[i] == '('
        depth -= 1 if block[i] == ')'
        if depth == 0
          end_idx = i
          break
        end
      end
      return nil unless end_idx

      license_form = block[(idx + 9)..end_idx] # skip "(license "

      if license_form.start_with?('(list ')
        # Multiple licenses: (list license:expat license:asl2.0)
        list_content = license_form[6...-1] # strip "(list " and trailing ")"
        licenses = list_content.scan(/(?:license:)?([a-zA-Z0-9_.+-]+)/).flatten
        licenses.join(', ') if licenses.any?
      else
        # Single license: license:gpl3+ or gpl3+
        license_form.strip.sub(/\)\z/, '').sub(/\Alicense:/, '').strip.presence
      end
    end

    def parse_guix_dependencies(block)
      return [] if block.blank?
      block = strip_scheme_comments(block)

      deps = []

      input_mappings = {
        'inputs' => 'runtime',
        'propagated-inputs' => 'runtime',
        'native-inputs' => 'build',
      }

      input_mappings.each do |attr, kind|
        extract_scheme_list(block, attr).each do |dep_name|
          next if guix_builtin?(dep_name)

          deps << {
            package_name: dep_name,
            requirements: '*',
            kind: kind,
            optional: false,
            ecosystem: 'guix'
          }
        end
      end

      deps.uniq { |d| [d[:package_name], d[:kind]] }
    end

    def extract_scheme_list(content, attr)
      names = []

      # Match (inputs (list ...)) or (native-inputs (list ...)) etc.
      pattern = /\(#{Regexp.escape(attr)}\s+\(list\s/
      return names unless content =~ pattern

      # Get everything after the match
      remainder = $'.dup

      # Find balanced parens
      depth = 1 # We're already inside one paren from (list
      end_idx = 0

      remainder.each_char.with_index do |c, i|
        depth += 1 if c == '('
        depth -= 1 if c == ')'
        if depth == 0
          end_idx = i
          break
        end
        end_idx = i
      end

      list_content = remainder[0...end_idx]

      # Extract identifiers - package names in Guix are lowercase with hyphens
      list_content.scan(/\b([a-zA-Z][a-zA-Z0-9_-]*(?:\.[a-zA-Z0-9_-]+)*)\b/).flatten.each do |name|
        names << name
      end

      names.uniq
    end

    def guix_builtin?(name)
      %w[list modify-inputs append replace delete].include?(name)
    end

    def parse_license_from_location(location)
      return nil if location.blank?

      content = fetch_scheme_file(location)
      return nil if content.blank?

      line_number = location.split(':').last.to_i
      block = find_package_block(content, line_number)
      return nil if block.blank?

      parse_guix_license(block)
    rescue
      nil
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: nil,
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
      }
    end
  end
end
