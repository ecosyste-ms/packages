# frozen_string_literal: true

require "digest/sha2"
require "erb"
require "json"
require "open3"
require "rubygems/package"
require "zlib"

module Ecosystem
  class Openbsd < Base
    RUN_DEPENDS_TYPE = 0

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

      deps = sqlite3_json_dependency_paths(row["PathId"])
      deps.filter_map do |dep_path|
        next unless synced_port_present?(dep_path)

        {
          package_name: dep_path,
          requirements: "*",
          kind: "install",
          ecosystem: self.class.lowercase_name,
        }
      end
    end

    def maintainers_metadata(name)
      row = synced_port_for_name(name)
      return [] if row.blank?
      maint = row["MAINTAINER"]
      return [] if maint.blank?

      segments = maint.split("<", 2)
      display = segments.first.to_s.strip
      email = segments[1].to_s.gsub(">", "").strip
      email = "#{display.gsub(/\s+/, '-').downcase}@unknown" if email.blank?

      [{
        uuid: email,
        name: display.presence || email,
        url: "#{packages_base_url}/",
      }]
    end

    protected

    def packages_base_url
      @packages_base_url ||= @registry_url.sub(%r{/+\z}, "")
    end

    def synced_ports
      @synced_ports ||= load_synced_ports
    end

    def ports_by_path
      @ports_by_path ||= synced_ports.index_by { |row| row["FullPkgPath"] }
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

      tarball_names = index_map.keys
      tarball_set = tarball_names.each_with_object({}) do |basename, memo|
        memo[basename] = true
      end

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
      dedupe_port_rows(ports).select do |row|
        next false if row["FULLPKGNAME"].blank?

        tarball_set.include?("#{row["FULLPKGNAME"]}.tgz")
      end
    end

    def extract_share_sqlports(tgz_file)
      digest = Digest::SHA256.file(tgz_file).hexdigest
      sqlite_filename = "#{self.class.lowercase_name}-sqlports-#{digest}.sqlite".squeeze("-")
      sqlite_path = Rails.root.join("tmp", "cache", "ecosystems", sqlite_filename)
      FileUtils.mkdir_p(sqlite_path.dirname)
      return sqlite_path if sqlite_path.exist? && sqlite_path.size.positive?

      found = nil
      Zlib::GzipReader.open(tgz_file) do |gzip|
        Gem::Package::TarReader.new(gzip) do |reader|
          reader.each do |entry|
            next unless entry.file?

            next unless entry.full_name.delete_prefix("./") == "share/sqlports"

            found = entry.read
            break
          end
        end
      end

      if found.blank?
        File.delete(sqlite_path) if sqlite_path.exist?
        return sqlite_path
      end

      File.binwrite(sqlite_path, found)
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

    def sqlite3_dependency_sql(path_id)
      <<~SQL.squish
        SELECT DISTINCT dp.FullPkgPath AS dep_path
        FROM _Depends d
        JOIN _Paths p ON p.Id = d.FullPkgPath
        JOIN _Paths dp ON dp.Id = d.DependsPath
        WHERE p.Id = #{Integer(path_id)} AND CAST(d.Type AS INTEGER) = #{RUN_DEPENDS_TYPE}
        ORDER BY dp.FullPkgPath ASC
      SQL
    end

    def sqlite3_json_dependency_paths(path_id)
      return [] if @sqlports_database_path.nil? || !@sqlports_database_path.exist? || @sqlports_database_path.size.zero?

      sqlite3_exec_json(sqlite3_dependency_sql(path_id), database: @sqlports_database_path).map do |entry|
        entry.fetch("dep_path", nil).presence || entry.fetch(:dep_path, nil)&.presence
      end.compact.uniq.map(&:to_s).reject(&:blank?)
    end

    def sqlite3_exec_json(sql, database: @sqlports_database_path)
      return [] if database.nil? || !database.exist? || database.size.zero?

      out, status =
        Open3.capture2(
          "sqlite3",
          "-readonly",
          database.to_path,
          "-json",
          sql,
          err: File::NULL
        )
      return [] unless status.success?

      out = out.to_s.strip
      return [] if out.blank?

      JSON.parse(out, symbolize_names: false)
    rescue JSON::ParserError => e
      Rails.logger.warn("OpenBSD sqlite3 JSON parse failure: #{e.message}")
      []
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
      matches.max_by(&:length)
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
      stem = row["PKGSTEM"].to_s
      return full if stem.blank?

      prefix = "#{stem}-"
      return full.delete_prefix(prefix) if full.start_with?(prefix)

      full
    end

    def inferred_architecture
      @registry&.metadata&.dig("arch")&.presence ||
        @registry&.metadata&.dig("architecture")&.presence ||
        @registry_url.to_s.scan(%r{/packages/([^/]+)/?}).flatten.last
    end
  end
end
