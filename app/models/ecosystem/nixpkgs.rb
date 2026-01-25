# frozen_string_literal: true

module Ecosystem
  class Nixpkgs < Base
    def self.purl_type
      'nix'
    end

    def sync_in_batches?
      true
    end

    def registry_url(package, _version = nil)
      "https://search.nixos.org/packages?channel=#{channel}&query=#{package.name}"
    end

    def install_command(package, _version = nil)
      "nix-env -iA nixpkgs.#{package.name}"
    end

    def documentation_url(package, _version = nil)
      position = package.metadata&.dig('position')
      return nil unless position.present?

      file_path, line = position.split(':')
      "https://github.com/NixOS/nixpkgs/blob/nixos-#{channel}/#{file_path}#L#{line}"
    end

    def check_status(package)
      pkg = fetch_package_metadata(package.name)
      return 'removed' if pkg.blank?
      nil
    end

    def channel
      @registry.version || 'unstable'
    end

    def packages_url
      "https://channels.nixos.org/nixos-#{channel}/packages.json.br"
    end

    def packages
      # Use class-level cache keyed by channel to avoid re-downloading
      # when new ecosystem instances are created (e.g., from package.registry)
      @@packages_cache ||= {}
      @@packages_cache[channel] ||= load_packages_json
    end

    def self.clear_packages_cache!
      @@packages_cache = {}
    end

    def load_packages_json
      json_file = download_and_cache_packages
      Rails.logger.info "[Nixpkgs] Loading packages from cached file: #{json_file}"
      data = Oj.load(File.read(json_file))
      data['packages'] || {}
    end

    def download_and_cache_packages(ttl: 1.hour)
      cache_dir = Rails.root.join('tmp', 'cache', 'ecosystems', 'nixpkgs')
      FileUtils.mkdir_p(cache_dir)
      cached_file = cache_dir.join("packages-#{channel}.json")

      if cached_file.exist? && cached_file.mtime > ttl.ago
        Rails.logger.info "[Nixpkgs] Using cached packages.json for #{channel} (age: #{((Time.now - cached_file.mtime) / 60).round}m)"
        return cached_file
      end

      Rails.logger.info "[Nixpkgs] Downloading packages.json.br for #{channel} from #{packages_url}"

      response = download_packages_json
      raise "Failed to download packages.json.br from #{packages_url}: #{response.status}" unless response.success?

      decompressed = Brotli.inflate(response.body)
      File.write(cached_file, decompressed)
      Rails.logger.info "[Nixpkgs] Cached packages.json for #{channel} (#{(File.size(cached_file) / 1024.0 / 1024.0).round(1)}MB)"

      cached_file
    end

    def download_packages_json
      connection = Faraday.new(packages_url) do |builder|
        builder.use Faraday::FollowRedirects::Middleware
        builder.request :retry, { max: 3, interval: 0.5, backoff_factor: 2 }
        builder.adapter Faraday.default_adapter
      end
      connection.get
    end

    def all_package_names
      packages.keys
    end

    def recently_updated_package_names
      # nixpkgs doesn't have timestamps in packages.json
      # fall back to watching the GitHub repo commits
      url = "https://github.com/NixOS/nixpkgs/commits/nixos-#{channel}.atom"
      begin
        feed = SimpleRSS.parse(get_raw(url))
        # Extract package names from commit titles like "package-name: 1.0 -> 1.1"
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

    def fetch_package_metadata(name)
      packages[name]
    end

    # Override to pass the attribute path (hash key) to map_package_metadata
    def package_metadata(name)
      pkg = fetch_package_metadata(name)
      map_package_metadata(pkg, name)
    end

    def map_package_metadata(pkg, attribute_path = nil)
      return false if pkg.blank? || pkg['pname'].blank?

      meta = pkg['meta'] || {}
      name = attribute_path || pkg['pname']

      # Infer upstream source from attribute path
      upstream = infer_upstream_from_attribute_path(name, pkg['pname'])

      # Use the full nix attribute path (e.g. "python313Packages.numpy") as the name
      # since pname alone isn't unique in nixpkgs
      {
        name: name,
        description: meta['description'],
        homepage: meta['homepage'],
        licenses: map_licenses(meta['license']),
        repository_url: repo_fallback('', meta['homepage']),
        keywords_array: extract_keywords(pkg),
        metadata: {
          nix_attribute: pkg['name'],
          position: meta['position'],
          platforms: meta['platforms'],
          broken: meta['broken'],
          insecure: meta['insecure'],
          unfree: meta['unfree'],
          outputs: pkg['outputs']&.keys,
          upstream_ecosystem: upstream&.dig(:ecosystem),
          upstream_name: upstream&.dig(:name),
          upstream_purl: upstream&.dig(:purl),
        }.compact
      }
    end

    # Infer upstream ecosystem from nix attribute path
    # e.g., python311Packages.requests -> pypi/requests
    def infer_upstream_from_attribute_path(attribute_path, pname)
      # Map attribute path prefixes to ecosyste.ms ecosystem names
      # Patterns handle version numbers in prefixes (e.g., python312Packages, perl538Packages)
      prefix_mappings = {
        /^python\d*Packages\./ => 'pypi',
        /^rubyPackages\./ => 'rubygems',
        /^nodePackages(?:_latest)?\./ => 'npm',
        /^perl\d*Packages\./ => 'cpan',
        /^haskellPackages\./ => 'hackage',
        /^ocamlPackages\./ => 'opam',
        /^lua\d*Packages\./ => 'luarocks',
        /^luajitPackages\./ => 'luarocks',
        /^rPackages\./ => 'cran',
        /^beamPackages\./ => 'hex',
        /^emacsPackages\./ => 'elpa',
        /^coqPackages\./ => 'opam',
        /^idrisPackages\./ => 'hackage',
        /^octavePackages\./ => 'octave',
        /^chickenPackages_\d+\./ => 'chicken',
        /^akkuPackages\./ => 'akku',
      }

      prefix_mappings.each do |pattern, ecosystem|
        next unless attribute_path =~ pattern

        # Extract the package name (after the prefix)
        upstream_name = attribute_path.sub(pattern, '')

        # Build PURL
        purl = build_upstream_purl(ecosystem, upstream_name)

        return {
          ecosystem: ecosystem,
          name: upstream_name,
          purl: purl
        }
      end

      nil
    end

    def map_licenses(license_data)
      return nil if license_data.blank?

      case license_data
      when Hash
        license_data['spdxId'] || license_data['shortName']
      when Array
        license_data.map { |l| l.is_a?(Hash) ? (l['spdxId'] || l['shortName']) : l }.compact.join(', ')
      else
        license_data.to_s
      end
    end

    def extract_keywords(pkg)
      keywords = []
      meta = pkg['meta'] || {}

      # Add isBuildPythonPackage etc as keywords
      meta.each do |key, value|
        if key.start_with?('isBuild') && value.present?
          keywords << key.sub('isBuild', '').sub('Package', '').downcase
        end
      end

      keywords
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      pkg = fetch_package_metadata(pkg_metadata[:name])
      return [] if pkg.blank?

      meta = pkg['meta'] || {}

      [
        {
          number: pkg['version'],
          licenses: map_licenses(meta['license']),
          metadata: {
            nix_attribute: pkg['name'],
            system: pkg['system'],
            outputs: pkg['outputs']&.keys,
          }.compact
        }
      ]
    end

    def maintainers_metadata(name)
      pkg = fetch_package_metadata(name)
      return [] if pkg.blank?

      maintainers = pkg.dig('meta', 'maintainers') || []
      maintainers.map do |m|
        next if m.blank?

        {
          uuid: m['github'] || m['email'] || m['name'],
          name: m['name'],
          email: m['email'],
          url: m['github'].present? ? "https://github.com/#{m['github']}" : nil,
        }.compact
      end.compact
    end

    def maintainer_url(maintainer)
      "https://github.com/#{maintainer.login}" if maintainer.login.present?
    end

    def purl_params(package, version = nil)
      {
        type: purl_type,
        namespace: nil,
        name: package.name.encode('iso-8859-1'),
        version: version.try(:number).try(:encode, 'iso-8859-1'),
        qualifiers: { 'channel' => channel }
      }
    end

    def dependencies_metadata(name, _version, _package)
      pkg = fetch_package_metadata(name)
      return [] if pkg.blank?

      position = pkg.dig('meta', 'position')
      return [] if position.blank?

      nix_content = fetch_nix_file(position)
      return [] if nix_content.blank?

      parse_nix_dependencies(nix_content)
    rescue => e
      Rails.logger.warn "[Nixpkgs] Failed to fetch dependencies for #{name}: #{e.message}"
      []
    end

    def fetch_nix_file(position)
      file_path = position.split(':').first
      url = "https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-#{channel}/#{file_path}"
      get_raw(url)
    rescue
      nil
    end

    def parse_nix_dependencies(content)
      deps = []

      # Extract function arguments: { lib, stdenv, fetchFromGitHub, numpy, blas }:
      # For simple files this works; for complex files we fall back to just using buildInputs
      all_args = extract_function_args(content)

      # Map input types to dependency kinds
      input_mappings = {
        'buildInputs' => 'runtime',
        'propagatedBuildInputs' => 'runtime',
        'nativeBuildInputs' => 'build',
        'nativeCheckInputs' => 'test',
        'checkInputs' => 'test'
      }

      input_mappings.each do |attr, kind|
        extract_nix_list(content, attr).each do |dep_name|
          # If we found function args, use them to validate deps
          # Otherwise, trust buildInputs but filter aggressively
          if all_args.any?
            next unless all_args.include?(dep_name)
          end
          next if nix_builtin?(dep_name)

          deps << {
            package_name: dep_name,
            requirements: '*',
            kind: kind,
            optional: false,
            ecosystem: 'nixpkgs'
          }
        end
      end

      deps.uniq { |d| [d[:package_name], d[:kind]] }
    end

    def extract_function_args(content)
      return [] if content.blank?

      # Find balanced braces using character iteration (safe from ReDoS)
      stripped = content.lstrip
      return [] unless stripped.start_with?('{')

      depth = 0
      end_pos = nil
      stripped.each_char.with_index do |c, i|
        depth += 1 if c == '{'
        depth -= 1 if c == '}'
        if depth == 0
          end_pos = i
          break
        end
      end

      return [] unless end_pos

      # Check that this is a function definition (followed by :)
      after_brace = stripped[end_pos + 1..]
      return [] unless after_brace&.lstrip&.start_with?(':')

      args_block = stripped[1...end_pos]
      args_block.scan(/\b([a-zA-Z_][a-zA-Z0-9_'-]*)\b/).flatten.uniq
    end

    def extract_nix_list(content, attr)
      # Match patterns like:
      #   buildInputs = [ foo bar baz ];
      #   buildInputs = [ foo ] ++ optionals cond [ bar ];
      #   buildInputs = with pkgs; [ foo bar ];
      names = []

      # Find the start of the attribute assignment
      start_pattern = /\b#{attr}\s*=/
      return names unless content =~ start_pattern

      # Get everything after "attr ="
      remainder = $'.dup

      # Find the end of the statement by tracking bracket depth
      depth = 0
      end_idx = 0

      remainder.each_char.with_index do |c, i|
        if c == '['
          depth += 1
        elsif c == ']'
          depth -= 1
        elsif c == ';' && depth == 0
          end_idx = i
          break
        end
        end_idx = i
      end

      block = remainder[0..end_idx]

      # Extract identifiers from within all [ ] brackets
      block.scan(/\[\s*([^\]]*)\]/m).flatten.each do |list_content|
        list_content.scan(/\b([a-zA-Z_][a-zA-Z0-9_'-]*)\b/).flatten.each do |name|
          names << name
        end
      end

      names.uniq
    end

    def nix_builtin?(name)
      %w[
        lib stdenv stdenvNoCC fetchurl fetchFromGitHub fetchFromGitLab fetchgit
        fetchzip fetchpatch makeWrapper writeText writeScript runCommand
        symlinkJoin buildEnv callPackage mkDerivation overrideAttrs
        optional optionals mkIf then else if inherit src version pname
        meta maintainers platforms homepage description license
      ].include?(name)
    end

    # Extract upstream package source information from nix file content
    # Returns hash with :ecosystem, :name, and :purl keys
    def extract_upstream_source(content)
      return nil if content.blank?

      # Detect the builder type and map to ecosyste.ms ecosystem name
      # Priority: more specific patterns first
      ecosystem, name = detect_upstream_from_builder(content) ||
                        detect_upstream_from_fetcher(content) ||
                        [nil, nil]

      return nil if ecosystem.blank? || name.blank?

      {
        ecosystem: ecosystem,
        name: name,
        purl: build_upstream_purl(ecosystem, name)
      }
    end

    def detect_upstream_from_builder(content)
      # Map builder functions to ecosystems
      builder_mappings = [
        [/\bbuildPythonPackage\b/, 'pypi', :extract_python_package_name],
        [/\brustPlatform\.buildRustPackage\b|\bbuildRustPackage\b/, 'cargo', :extract_pname],
        [/\bbuildNpmPackage\b/, 'npm', :extract_pname],
        [/\bbuildGoModule\b/, 'go', :extract_pname],
        [/\bbuildRubyGem\b|\bbundlerEnv\b/, 'rubygems', :extract_ruby_gem_name],
        [/\bbuildPerlPackage\b/, 'cpan', :extract_pname],
        [/\bbuildLuarocksPackage\b/, 'luarocks', :extract_pname],
        [/\bhaskellPackages\.mkDerivation\b/, 'hackage', :extract_pname],
        [/\bbuildRPackage\b/, 'cran', :extract_pname],
        [/\bbuildMix\b|\bbuildRebar3\b/, 'hex', :extract_pname],
        [/\bbuildElmPackage\b/, 'elm', :extract_pname],
        [/\bbuildComposerProject\b/, 'packagist', :extract_pname],
        [/\bbuildDotnetModule\b/, 'nuget', :extract_pname],
        [/\bbuildFlutterApplication\b/, 'pub', :extract_pname],
        [/\bbuildDubPackage\b/, 'dub', :extract_pname],
        [/\bbuildNimPackage\b/, 'nimble', :extract_pname],
        [/\bbuildCrystal\b/, 'shards', :extract_pname],
        [/\bswiftPackages\.buildSwiftPackage\b/, 'swiftpm', :extract_pname],
        [/\bbuildMaven\b/, 'maven', :extract_pname],
        [/\bbuildClojure\b/, 'clojars', :extract_pname],
      ]

      builder_mappings.each do |pattern, ecosystem, extractor|
        next unless content =~ pattern
        name = send(extractor, content)
        return [ecosystem, name] if name.present?
      end

      nil
    end

    def detect_upstream_from_fetcher(content)
      # Some packages use specific fetchers that indicate upstream source
      fetcher_mappings = [
        [/\bfetchPypi\b/, 'pypi', :extract_python_package_name],
        [/\bfetchCrate\b/, 'cargo', :extract_crate_name],
        [/\bfetchHex\b/, 'hex', :extract_hex_name],
        [/\bfetchNuGet\b/, 'nuget', :extract_pname],
        [/\bfetchMaven\b/, 'maven', :extract_pname],
      ]

      fetcher_mappings.each do |pattern, ecosystem, extractor|
        next unless content =~ pattern
        name = send(extractor, content)
        return [ecosystem, name] if name.present?
      end

      nil
    end

    def extract_pname(content)
      # Match pname = "value"; or pname = value;
      if content =~ /\bpname\s*=\s*"([^"]+)"/
        $1
      elsif content =~ /\bpname\s*=\s*([a-zA-Z_][a-zA-Z0-9_-]*)\s*;/
        # pname = somevariable; - can't resolve, skip
        nil
      else
        nil
      end
    end

    def extract_python_package_name(content)
      # First check fetchPypi for explicit pname
      if content =~ /\bfetchPypi\s*\{[^}]*\bpname\s*=\s*"([^"]+)"/m
        return $1
      end

      # Check for fetchPypi with inherit pname - use the file's pname
      if content =~ /\bfetchPypi\s*\{[^}]*\binherit\s+pname\b/m
        pname = extract_pname(content)
        return pname if pname.present?
      end

      # Fall back to pname - buildPythonPackage usually means PyPI
      extract_pname(content)
    end

    def extract_go_module_name(content)
      # Go packages might have a modRoot or importPath
      # For now, use pname as a fallback
      extract_pname(content)
    end

    def extract_ruby_gem_name(content)
      # Ruby gems use gemName attribute
      if content =~ /\bgemName\s*=\s*"([^"]+)"/
        $1
      else
        extract_pname(content)
      end
    end

    def extract_crate_name(content)
      # fetchCrate uses crateName or pname
      if content =~ /\bfetchCrate\s*\{[^}]*\bcrateName\s*=\s*"([^"]+)"/m
        $1
      elsif content =~ /\bfetchCrate\s*\{[^}]*\binherit\s+pname\b/m
        extract_pname(content)
      else
        extract_pname(content)
      end
    end

    def extract_hex_name(content)
      # fetchHex uses pkg attribute
      if content =~ /\bfetchHex\s*\{[^}]*\bpkg\s*=\s*"([^"]+)"/m
        $1
      elsif content =~ /\bfetchHex\s*\{[^}]*\binherit\s+pname\b/m
        extract_pname(content)
      else
        extract_pname(content)
      end
    end

    def build_upstream_purl(ecosystem, name)
      return nil if ecosystem.blank? || name.blank?

      # Map ecosyste.ms ecosystem names to PURL types
      # https://github.com/package-url/purl-spec/blob/master/PURL-TYPES.rst
      purl_type = case ecosystem
      when 'pypi' then 'pypi'
      when 'cargo' then 'cargo'
      when 'npm' then 'npm'
      when 'go' then 'golang'
      when 'rubygems' then 'gem'
      when 'cpan' then 'cpan'
      when 'luarocks' then 'luarocks'
      when 'hackage' then 'hackage'
      when 'opam' then 'opam'
      when 'cran' then 'cran'
      when 'hex' then 'hex'
      when 'elm' then 'elm'
      when 'packagist' then 'composer'
      when 'nuget' then 'nuget'
      when 'pub' then 'pub'
      when 'maven' then 'maven'
      when 'clojars' then 'clojars'
      when 'swiftpm' then 'swift'
      when 'shards' then nil # No standard PURL type for Crystal shards
      when 'dub' then nil # No standard PURL type for D packages
      when 'nimble' then nil # No standard PURL type for Nim packages
      when 'elpa' then nil # No standard PURL type for ELPA
      else
        return nil
      end

      return nil if purl_type.blank?
      "pkg:#{purl_type}/#{name}"
    end
  end
end
