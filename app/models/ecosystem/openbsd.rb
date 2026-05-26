# frozen_string_literal: true

module Ecosystem
  class Openbsd < Base
    DEPENDENCY_KINDS_BY_TYPE = {
      0 => "runtime",
      1 => "runtime",
      2 => "build",
    }.freeze

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
      parts = package.name.split("/")
      if parts.length > 1
        namespace = parts[0..-2].join("/")
        name = parts.last
      else
        namespace = nil
        name = parts.first
      end
      q = {}
      arch = inferred_architecture
      q["arch"] = arch if arch.present?
      {
        type: purl_type,
        namespace: namespace,
        name: name.encode("ISO-8859-1"),
        version: version.try(:number).try(:encode, "ISO-8859-1"),
        qualifiers: q.presence || nil,
      }
    end

    def registry_url(package = nil, _version = nil)
      return nil if package.blank?

      pkgpath = package.name.split(",", 2).first.to_s.strip
      return nil if pkgpath.blank?

      "https://cvsweb.openbsd.org/cgi-bin/cvsweb/ports/#{pkgpath}/"
    end

    def download_url(package, _version = nil)
      metadata = fetch_package_metadata(package.name)
      return nil if metadata.blank?

      fullpkgname = metadata["FULLPKGNAME"]
      return nil if fullpkgname.blank?
      "#{packages_base_url}/#{ERB::Util.url_encode("#{fullpkgname}.tgz")}"
    end

    def install_command(package, _version = nil)
      "pkg_add #{fetch_package_metadata(package.name)&.dig("FULLPKGNAME") || package.name}"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def all_package_names
      ports_by_path.keys
    end

    def recently_updated_package_names
      timed = synced_ports.map do |row|
        key = tarball_basename(row)
        stamp = tarball_mtime(key)
        [row["FullPkgPath"], stamp || Time.zone.at(0)]
      end
      timed.sort_by(&:last).last(100).reverse.map(&:first)
    end

    def fetch_package_metadata_uncached(name)
      ports_by_path[name]
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank?

      full_path = pkg_metadata["FullPkgPath"]
      homepage = pkg_metadata["HOMEPAGE"].presence

      {
        name: full_path,
        description: pkg_metadata["COMMENT"].presence,
        homepage: homepage,
        licenses: nil,
        repository_url: find_repository_url([homepage]),
        namespace: namespace_for_path(full_path),
        metadata: {
          pkgstem: pkg_metadata["PKGSTEM"],
          fullpkgname: pkg_metadata["FULLPKGNAME"],
          subpackage: pkg_metadata["SUBPACKAGE"],
        }.compact,
      }
    end

    def versions_metadata(pkg_metadata, _existing_version_numbers = [])
      row = synced_port_for_name(pkg_metadata[:name])
      return [] if row.blank?

      num = pkg_version_number(row)
      return [] if num.blank?

      key = tarball_basename(row)
      [
        {
          number: num,
          published_at: tarball_mtime(key),
          licenses: nil,
          metadata: {
            fullpkgname: row["FULLPKGNAME"],
          },
        },
      ]
    end

    def dependencies_metadata(name, _version, _pkg_metadata)
      row = synced_port_for_name(name)
      return [] if row.blank?

      Array(dependency_rows_by_path_id[row["PathId"].to_i]).filter_map do |dep|
        dep_path = dep[:path]
        next unless synced_port_present?(dep_path)

        {
          package_name: dep_path,
          requirements: "*",
          kind: dep[:kind],
          ecosystem: self.class.lowercase_name,
        }
      end
    end

    def maintainers_metadata(name)
      row = synced_port_for_name(name)
      return [] if row.blank?
      maint = row["MAINTAINER"]
      return [] if maint.blank?

      maint.scan(/([^<,]+)?<([^>]+)>/).filter_map do |display, email|
        email = email.to_s.strip
        next if email.blank?

        {
          uuid: email,
          name: display.to_s.strip.presence || email,
          email: email,
        }
      end
    end

    def packages_base_url
      @packages_base_url ||= @registry_url.sub(%r{/+\z}, "")
    end

    def synced_ports
      @synced_ports ||= load_synced_ports
    end

    def ports_by_path
      @ports_by_path ||= synced_ports.index_by { |row| row["FullPkgPath"] }
    end

    def dependency_rows_by_path_id
      @dependency_rows_by_path_id ||= {}
    end

    def synced_port_for_name(path)
      ports_by_path[path]
    end

    def synced_port_present?(path)
      ports_by_path.key?(path)
    end

    def tarball_basename(row)
      "#{row["FULLPKGNAME"]}.tgz"
    end

    def tarball_mtime(basename)
      load_index_basenames[basename]&.[](:mtime)
    end

    def load_index_basenames
      @index_entries ||= fetch_index_basenames_with_times
    end

    def fetch_index_basenames_with_times
      idx_url = "#{packages_base_url}/index.txt"
      cache_key =
        "#{self.class.lowercase_name}-#{@registry.name&.parameterize || 'unknown'}-index.txt".squeeze("-")
      file = download_and_cache(idx_url, cache_key, ttl: 6.hours)
      return {} if file.nil? || !file.exist?

      entries = {}
      File.foreach(file) do |raw|
        line = raw.chomp
        parts = line.split
        basename = parts.last
        next if basename.blank? || !basename.end_with?(".tgz")
        next if basename.delete_prefix(".").start_with?("debug-")

        stamp = ls_listing_timestamp(parts)
        entries[basename] = {mtime: stamp || Time.zone.at(0)}
      end
      entries
    end

    # parts: `-rw-r--r-- ... size Mon DD hh:mm:ss YYYY name.tgz`
    def ls_listing_timestamp(parts)
      return nil unless parts.size >= 9

      year = Integer(parts[-2])
      time_token = "#{parts[-5]} #{parts[-4]} #{parts[-3]} #{year}"
      Time.find_zone!("UTC").parse(time_token)
    rescue ArgumentError, TypeError
      nil
    end

    def load_synced_ports
      index_map = load_index_basenames

      sqlports_pkg = resolved_sqlports_tgz_filename
      return [] if sqlports_pkg.blank?

      sqlports_url = "#{packages_base_url}/#{sqlports_pkg}"
      cached_tgz_key =
        "#{self.class.lowercase_name}-#{sqlports_pkg.parameterize.presence || Digest::SHA256.hexdigest(sqlports_url)}".squeeze("-")

      cached_tgz_path = download_and_cache(sqlports_url, cached_tgz_key, ttl: 6.hours)
      return [] if cached_tgz_path.blank? || !cached_tgz_path.exist?

      @sqlports_database_path = extract_share_sqlports(cached_tgz_path)
      return [] unless @sqlports_database_path.exist? && @sqlports_database_path.size.positive?

      ports = sqlite3_exec_json(select_ports_sql)
      synced = dedupe_port_rows(ports).select do |row|
        next false if row["FULLPKGNAME"].blank?

        index_map.key?("#{row["FULLPKGNAME"]}.tgz")
      end
      @dependency_rows_by_path_id = build_dependency_index(synced)
      synced
    end

    def extract_share_sqlports(tgz_file)
      digest = Digest::SHA256.file(tgz_file).hexdigest
      sqlite_filename = "#{self.class.lowercase_name}-sqlports-#{digest}.sqlite".squeeze("-")
      sqlite_path = Rails.root.join("tmp", "cache", "ecosystems", sqlite_filename)
      FileUtils.mkdir_p(sqlite_path.dirname)
      return sqlite_path if sqlite_path.exist? && sqlite_path.size.positive?

      Dir.mktmpdir("openbsd-sqlports") do |dir|
        ok = system("tar", "-xzf", tgz_file.to_s, "-C", dir, "share/sqlports")
        extracted = File.join(dir, "share", "sqlports")

        unless ok && File.exist?(extracted)
          File.delete(sqlite_path) if sqlite_path.exist?
          return sqlite_path
        end

        FileUtils.cp(extracted, sqlite_path)
      end

      sqlite_path
    rescue StandardError => e
      Rails.logger.error("Unable to unpack OpenBSD sqlports database from #{tgz_file}: #{e.message}")
      invalid = Rails.root.join("tmp", "cache", "ecosystems", "#{self.class.lowercase_name}-sqlports-invalid.sqlite")
      File.delete(invalid) if invalid.exist?
      invalid
    end

    def select_ports_sql
      <<~SQL.squish
        SELECT PathId,
               FullPkgPath,
               PKGNAME,
               COMMENT,
               HOMEPAGE,
               FULLPKGNAME,
               PKGSTEM,
               SUBPACKAGE,
               MAINTAINER
        FROM PortsQ
        WHERE FULLPKGNAME IS NOT NULL AND TRIM(FULLPKGNAME) != ''
      SQL
    end

    def dedupe_port_rows(rows)
      priority = lambda do |row|
        path = row["FullPkgPath"].to_s
        subpkg_rank = path.include?(",-") ? 1 : 0
        [subpkg_rank, path.length, row["FullPkgPath"], row["PathId"].to_i]
      end

      grouped = rows.group_by { |r| r["FULLPKGNAME"] }
      grouped.map do |_fullname, siblings|
        siblings.min_by(&priority)
      end
    end

    def select_dependencies_sql
      <<~SQL.squish
        SELECT PathId AS path_id,
               DependsPath AS dep_path,
               CAST(Type AS INTEGER) AS type
        FROM Depends
        WHERE CAST(Type AS INTEGER) IN (#{DEPENDENCY_KINDS_BY_TYPE.keys.join(',')})
        ORDER BY path_id ASC, dep_path ASC
      SQL
    end

    def build_dependency_index(ports)
      synced_path_ids = ports.each_with_object({}) { |row, memo| memo[row["PathId"].to_i] = true }

      sqlite3_exec_json(select_dependencies_sql).each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, memo|
        path_id = row["path_id"].to_i
        next unless synced_path_ids[path_id]

        kind = DEPENDENCY_KINDS_BY_TYPE[row["type"].to_i]
        dep_path = row["dep_path"].to_s
        next if kind.blank? || dep_path.blank?

        memo[path_id] << { path: dep_path, kind: kind }
      end.transform_values { |deps| deps.uniq }
    end

    def sqlite3_exec_json(sql, database: @sqlports_database_path)
      return [] if database.nil? || !database.exist? || database.size.zero?

      db = SQLite3::Database.new(database.to_s, readonly: true)
      db.results_as_hash = true
      db.execute(sql).map do |row|
        row.each_with_object({}) do |(key, value), memo|
          memo[key] = value if key.is_a?(String)
        end
      end
    rescue SQLite3::Exception => e
      Rails.logger.warn("OpenBSD sqlite failure: #{e.message}")
      []
    ensure
      db&.close
    end

    def resolved_sqlports_tgz_filename
      direct = @registry&.metadata&.dig("sqlports_tgz")&.presence
      return direct if direct.present?

      discovered = discover_sqlports_tgz_filename
      return discovered if discovered.present?

      ver = @registry&.metadata&.dig("sqlports_version")
      return "sqlports-#{ver}.tgz" if ver.present?

      nil
    end

    def discover_sqlports_tgz_filename
      body = get_raw("#{packages_base_url}/")
      matches = body.to_s.scan(/href="(sqlports-[\d.]+\.tgz)"/i).flatten
      matches.max_by { |match| Gem::Version.new(match[/sqlports-([\d.]+)\.tgz/i, 1]) }
    rescue StandardError => e
      Rails.logger.warn("Unable to discover OpenBSD sqlports bundle: #{e.message}")
      nil
    end

    def namespace_for_path(path)
      return nil if path.blank?

      stem = path.split(",", 2).first.to_s.split("/").first
      stem.presence
    end

    def pkg_version_number(row)
      full = row["FULLPKGNAME"].to_s
      match = full.match(/\A(.+)-(\d.*)\z/)
      match && match[2]
    end

    def inferred_architecture
      @registry&.metadata&.dig("arch")&.presence ||
        @registry&.metadata&.dig("architecture")&.presence ||
        @registry_url.to_s.scan(%r{/packages/([^/]+)/?}).flatten.last
    end
  end
end
