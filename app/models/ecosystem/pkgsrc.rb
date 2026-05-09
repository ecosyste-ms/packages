# frozen_string_literal: true

require "zlib"

module Ecosystem
  class Pkgsrc < Base
    DEFAULT_SUMMARY_FILENAME = "pkg_summary.gz"

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def pkg_summary_url
      "#{@registry_url.chomp('/')}/#{registry_summary_filename}"
    end

    def registry_summary_filename
      @registry.metadata&.dig("pkg_summary_filename") ||
        @registry.metadata&.dig(:pkg_summary_filename) ||
        DEFAULT_SUMMARY_FILENAME
    end

    def cache_slug
      @cache_slug ||= Digest::MD5.hexdigest(pkg_summary_url)[0, 12]
    end

    def pkg_summary_archive_path
      download_and_cache(
        pkg_summary_url,
        "pkgsrc-pkg-summary-#{cache_slug}.gz",
        ttl: 1.hour
      )
    end

    def purl_params(package, version = nil)
      pkgpath = package.name.to_s
      cat, slash, remainder = pkgpath.partition("/")

      qualifiers = {}
      qualifiers["arch"] = package.metadata["machine_arch"] if package.metadata["machine_arch"].present?
      qualifiers["os"] = package.metadata["opsys"] if package.metadata["opsys"].present?

      {
        type: "pkgsrc",
        namespace: slash.present? ? cat : nil,
        name: (slash.present? ? remainder : package.name).encode("iso-8859-1"),
        version: version.try(:number).try(:encode, "iso-8859-1"),
        qualifiers: qualifiers,
      }.compact_blank
    end

    def registry_url(package, _version = nil)
      pkgpath = package.name.to_s
      return nil if pkgpath.blank?

      "https://pkgsrc.se/#{pkgpath}"
    end

    def documentation_url(package, version = nil)
      registry_url(package, version)
    end

    def download_url(package, version)
      return nil unless version.present?

      rec = record_matching_version(package.name, version.number)
      fn = rec&.fetch("FILE_NAME", nil).presence

      fn.present? ? "#{@registry_url.chomp('/')}/#{fn}" : nil
    end

    def install_command(package, version = nil)
      slug = pkg_slug(package.name.to_s)

      return "pkg_add #{slug}" if version.blank?

      rec = record_matching_version(package.name, version.number)
      pname = rec&.fetch("PKGNAME", nil)

      pname.present? ? "pkg_add #{pname}" : "pkg_add #{slug}-#{version.number}"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def build_index
      @records_by_pkgpath = Hash.new { |h, k| h[k] = [] }

      path = pkg_summary_archive_path

      unless path.present? && File.exist?(path.to_s)
        Rails.logger.warn("Pkgsrc #{registry.name}: missing #{pkg_summary_url}")
        @records_by_pkgpath = {}
        return @records_by_pkgpath
      end

      open_summary_lines(path.to_s) { |reader| parse_summary_stream(reader) }

      @records_by_pkgpath
    rescue StandardError => e
      Rails.logger.error("Pkgsrc #{registry.name}: failed to load pkg_summary (#{pkg_summary_url}): #{e.message}")
      (@records_by_pkgpath = {})
    end

    def records_by_pkgpath
      @records_by_pkgpath || build_index
    end

    def all_package_names
      records_by_pkgpath.keys.sort
    end

    def recently_updated_package_names
      latest_ts = {}

      records_by_pkgpath.each do |pkgpath, records|
        t = records.map { |rec| parsed_build_date(rec["BUILD_DATE"]) }.compact.max
        latest_ts[pkgpath] = t if t
      end

      latest_ts.sort_by { |_p, tm| tm }.last(100).reverse.map(&:first)
    end

    def fetch_package_metadata_uncached(name)
      recs = records_by_pkgpath[name]&.dup
      return nil if recs.blank?

      { "name" => name, "records" => recs }
    end

    def map_package_metadata(pkg_metadata)
      recs = pkg_metadata["records"]
      return false if recs.blank?

      primary = primary_record(recs)
      homepage = normalize_homepage(primary["HOMEPAGE"])
      pkgpath = pkg_metadata["name"]

      {
        name: pkgpath,
        description: primary["COMMENT"].presence || primary["DESCRIPTION"].presence,
        homepage: homepage,
        licenses: primary["LICENSE"].presence,
        repository_url: find_repository_url([homepage].compact),
        keywords_array: category_tokens(primary["CATEGORIES"]),
        namespace: pkgpath.partition("/").first,
        metadata: {
          pkg_slug: pkg_slug(pkgpath),
          machine_arch: primary["MACHINE_ARCH"],
          opsys: primary["OPSYS"],
          pkgname_latest: primary["PKGNAME"],
        }.compact,
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      raw = fetch_package_metadata(pkg_metadata[:name] || pkg_metadata["name"])
      return [] if raw.blank?

      raw["records"].each_with_object([]) do |rec, acc|
        ver = version_string_for(rec)
        next if ver.blank? || existing_version_numbers.include?(ver)

        row = {
          number: ver,
          published_at: parsed_build_date(rec["BUILD_DATE"]),
          metadata: {
            pkgname: rec["PKGNAME"],
            file_name: rec["FILE_NAME"],
            machine_arch: rec["MACHINE_ARCH"],
          }.compact,
        }

        integrity = integrity_from_digest(rec["DIGEST"])
        row[:integrity] = integrity if integrity.present?

        acc << row.compact
      end
    end

    def dependencies_metadata(name, version, _pkg_metadata)
      raw = fetch_package_metadata(name)
      return [] if raw.blank?

      rec = raw["records"].find { |r| version_string_for(r) == version.to_s }
      deps = Array(rec&.fetch("DEPENDS", [])).flatten.compact.reject(&:blank?)

      deps.flat_map do |line|
        n, req = split_dep_token(line.to_s.strip)
        next [] if n.blank?

        [{
          package_name: n,
          requirements: req,
          kind: "runtime",
          ecosystem: self.class.name.demodulize.downcase,
        }]
      end
    end

    protected

    def open_summary_lines(path)
      if path.end_with?(".gz")
        Zlib::GzipReader.open(path) { |reader| yield reader }
      else
        File.open(path, "r") { |fh| yield fh }
      end
    end

    def parse_summary_stream(io)
      buf = Hash.new { |h, k| h[k] = [] }

      io.each_line do |line|
        line_enc = sanitize_line_encoding(line.to_s.chomp("\n"))

        if line_enc.strip.empty?
          ingest_raw_buffer(buf) unless buf.keys.empty?
          buf = Hash.new { |h, k| h[k] = [] }
          next
        end

        k, v = line_enc.split(/=/, 2)
        next unless k.present?

        buf[k.strip] << v.to_s
      end

      ingest_raw_buffer(buf) unless buf.keys.empty?
    end

    def sanitize_line_encoding(str)
      s = str.force_encoding("UTF-8")
      s.unicode_normalize(:nfc)
    rescue ArgumentError
      str.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    def ingest_raw_buffer(buf)
      rec = normalize_record_buffer(buf)
      pkgpath = rec["PKGPATH"].to_s.presence
      pkgname = rec["PKGNAME"].to_s.presence

      return if pkgpath.blank? || pkgname.blank?

      records_by_pkgpath[pkgpath] << rec
    end

    def normalize_record_buffer(buf)
      out = {}

      buf.each do |key, vals|
        case key
        when "DESCRIPTION"
          out[key] = vals.reject(&:blank?).join("\n").presence || ""
        when "DEPENDS"
          out[key] = vals.flatten.compact.reject(&:blank?).flat_map { |t| t.to_s.scan(/\S+/) }.uniq
        else
          out[key] = vals.last
        end
      end

      out["DEPENDS"] ||= []
      out
    end

    def primary_record(records)
      records.max_by do |rec|
        parsed_build_date(rec["BUILD_DATE"]) || Time.zone.at(0)
      end || records.first
    end

    def record_matching_version(pkgpath, version_number)
      raw = fetch_package_metadata_uncached(pkgpath)
      return nil if raw.blank?

      raw["records"].find { |r| version_string_for(r) == version_number.to_s }
    end

    def version_string_for(record)
      slug = pkg_slug(record["PKGPATH"].to_s)
      pkgname = record["PKGNAME"].to_s
      return nil if slug.blank? || pkgname.blank?

      pref = "#{slug}-"
      if pkgname.start_with?(pref)
        pkgname.delete_prefix(pref)
      else
        pkgname.partition("-")[2].presence || pkgname
      end
    end

    def pkg_slug(pkgpath)
      pkgpath.split("/").last.presence || pkgpath.presence
    end

    def parsed_build_date(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def normalize_homepage(h)
      h = h.to_s.strip
      h.start_with?("http://", "https://") ? h : nil
    end

    def category_tokens(categories_field)
      categories_field.blank? ? [] : categories_field.to_s.split(/\s+/).reject(&:blank?)
    end

    SPLIT_DEP_MARK = /\A([^<=>]+)((?:<=|>=|>|<|=).*)\z/

    def split_dep_token(token)
      trimmed = strip_dep_wrappers(token)
      return [nil, nil] if trimmed.blank?

      m = trimmed.match(SPLIT_DEP_MARK)
      return [m[1].strip, m[2].strip] if m

      [trimmed, "*"]
    end

    def strip_dep_wrappers(token)
      t = token.strip.sub(/\A\{[^}]+\}(\s*|:\S+)?/, "")
      t.strip
    end

    def integrity_from_digest(value)
      return nil if value.blank?

      raw = value.to_s.strip.downcase

      case raw
      when /\Asha512\s*[:(]\s*([0-9a-f]{128}|[0-9a-f]{64})\z/i then "sha512-#{Regexp.last_match(1)}"
      when /\Asha256\s*[:(]\s*([0-9a-f]{64}|[0-9a-f]{32})\z/i then "sha256-#{Regexp.last_match(1)}"
      end
    end
  end
end
