# frozen_string_literal: true

module Ecosystem
  class Gentoo < Base
    DEFAULT_SNAPSHOT_URL = "https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz"

    ATOM_RE = %r{
      \b
      ( [a-zA-Z0-9+][a-zA-Z0-9+._-]* / [a-zA-Z0-9+][a-zA-Z0-9+._-]*? )
      (?= -[0-9] | [\[\s:,;\)\|] | $ )
    }x

    def sync_in_batches?
      true
    end

    def has_dependent_repos?
      false
    end

    def snapshot_url
      @registry.metadata&.dig("snapshot_url") ||
        @registry.metadata&.dig(:snapshot_url) ||
        DEFAULT_SNAPSHOT_URL
    end

    def purl_params(package, version = nil)
      category, slash, pn = package.name.to_s.partition("/")

      {
        type: "gentoo",
        namespace: slash.present? ? category : nil,
        name: (slash.present? ? pn : package.name).encode("iso-8859-1"),
        version: version.try(:number).try(:encode, "iso-8859-1"),
      }.compact_blank
    end

    def registry_url(package, _version = nil)
      category, pn = package.name.to_s.split("/", 2)
      return "https://packages.gentoo.org/packages/search?q=#{ERB::Util.url_encode(package.name)}" if pn.blank?

      "https://packages.gentoo.org/packages/#{ERB::Util.url_encode(category)}/#{ERB::Util.url_encode(pn)}"
    end

    def documentation_url(package, _version = nil)
      registry_url(package)
    end

    def download_url(package, version)
      return nil unless version.present?

      rec = record_for_version(package.name, version.number)
      return nil if rec.blank?

      src = rec["SRC_URI"].to_s.split(/\s+/).find { |u| u.start_with?("http://", "https://") }
      src.presence
    end

    def install_command(package, version = nil)
      return "emerge #{package.name}" if version.blank?

      "emerge =#{package.name}-#{version.number}"
    end

    def check_status(package)
      return "removed" if fetch_package_metadata(package.name).blank?
    end

    def cache_slug
      @cache_slug ||= Digest::MD5.hexdigest(snapshot_url)[0, 12]
    end

    def md5_cache_root
      return @md5_cache_root if @md5_cache_root

      cached_xz = download_and_cache(
        snapshot_url,
        "gentoo-portage-#{cache_slug}.tar.xz",
        ttl: 1.hour
      )

      return nil if cached_xz.blank? || !File.exist?(cached_xz.to_s)

      dest = Rails.root.join("tmp", "cache", "ecosystems", "gentoo-md5-cache-#{cache_slug}")

      if !dest.directory? || File.mtime(dest) < File.mtime(cached_xz.to_s)
        FileUtils.rm_rf(dest)
        Dir.mktmpdir("gentoo-portage") do |dir|
          ok = system(
            "tar", "-xJf", cached_xz.to_s, "-C", dir,
            "portage/metadata/md5-cache"
          )
          extracted = File.join(dir, "portage", "metadata", "md5-cache")

          unless ok && File.directory?(extracted)
            Rails.logger.error("Gentoo #{registry.name}: failed to extract md5-cache from portage snapshot")
            return nil
          end

          FileUtils.mv(extracted, dest)
        end
      end

      @md5_cache_root = dest
    end

    def atom_paths
      return @atom_paths if @atom_paths

      root = md5_cache_root
      @atom_paths = Hash.new { |h, k| h[k] = [] }
      return @atom_paths if root.blank? || !root.directory?

      Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |p|
        next if File.directory?(p) || File.basename(p).start_with?(".")
        next if File.extname(p) == ".gz"

        rel = p.delete_prefix("#{root}/")
        category, pf = rel.split("/", 2)
        next if category.blank? || pf.blank?

        pn, pv = split_package_version(pf)
        next if pn.blank? || pv.blank?

        atom = "#{category}/#{pn}"
        @atom_paths[atom] << p
      end

      @atom_paths
    end

    def all_package_names
      atom_paths.keys.sort
    end

    def recently_updated_package_names
      pairs = []

      atom_paths.each do |atom, paths|
        latest = paths.map { |p| File.mtime(p) rescue nil }.compact.max
        pairs << [atom, latest] if latest
      end

      pairs.sort_by { |_a, t| t }.last(100).reverse.map(&:first)
    end

    def fetch_package_metadata_uncached(name)
      paths = atom_paths[name]
      return nil if paths.blank?

      records = paths.map { |path| parse_md5_cache_file(path) }
      { "name" => name, "paths" => paths, "records" => records }
    end

    def map_package_metadata(pkg_metadata)
      return false if pkg_metadata.blank?

      recs = pkg_metadata["records"]
      return false if recs.blank?

      primary = primary_record(recs, pkg_metadata["paths"])

      category, pn = pkg_metadata["name"].to_s.split("/", 2)
      homepage = primary["HOMEPAGE"].to_s.split(/\s+/).find { |u| u.start_with?("http://", "https://") }

      {
        name: pkg_metadata["name"],
        description: primary["DESCRIPTION"],
        homepage: homepage,
        licenses: primary["LICENSE"]&.tr("\t", " "),
        repository_url: find_repository_url([homepage].compact),
        keywords_array: primary["KEYWORDS"].to_s.split(/\s+/).reject(&:blank?),
        namespace: category,
        metadata: {
          category: category,
          slot: primary["SLOT"],
          eapi: primary["EAPI"],
          inherit: primary["INHERIT"],
          iuse: primary["IUSE"],
        }.compact,
      }
    end

    def versions_metadata(pkg_metadata, existing_version_numbers = [])
      raw = fetch_package_metadata(pkg_metadata[:name] || pkg_metadata["name"])
      return [] if raw.blank?

      raw["paths"].zip(raw["records"]).each_with_object([]) do |(path, rec), acc|
        pf = path.split("/").last
        _pn, pv = split_package_version(pf)
        next if pv.blank? || existing_version_numbers.include?(pv.to_s)

        sum = rec["_md5_"]
        acc << {
          number: pv,
          published_at: File.mtime(path),
          integrity: sum.present? ? "md5-#{sum}" : nil,
          metadata: {
            slot: rec["SLOT"],
            keywords: rec["KEYWORDS"],
            eapi: rec["EAPI"],
          }.compact,
        }.compact
      end
    end

    def dependencies_metadata(name, version, _pkg_metadata)
      raw = fetch_package_metadata(name)
      return [] if raw.blank?

      pf_path = raw["paths"].zip(raw["records"]).find do |path, rec|
        rec_path_pv(path) == version.to_s
      end&.first

      return [] if pf_path.blank?

      rec = parse_md5_cache_file(pf_path)
      deps = []

      deps += deps_from_field(rec["RDEPEND"], "runtime")
      deps += deps_from_field(rec["PDEPEND"], "runtime")
      deps += deps_from_field(rec["BDEPEND"], "build")
      deps += deps_from_field(rec["IDEPEND"], "install") if rec["IDEPEND"].present?

      deps.uniq { |d| [d[:package_name], d[:kind], d[:requirements]] }
    end

    protected

    def rec_path_pv(path)
      pf = path.split("/").last
      _, pv = split_package_version(pf)
      pv
    end

    def primary_record(recs, paths)
      idx = paths.each_with_index.max_by do |path, _i|
        File.mtime(path)
      rescue
        Time.zone.at(0)
      end&.last
      idx ||= 0

      recs[idx] || recs.last
    end

    def record_for_version(name, version_number)
      raw = fetch_package_metadata_uncached(name)
      return nil if raw.blank?

      raw["paths"].zip(raw["records"]).each do |path, rec|
        return rec if rec_path_pv(path) == version_number.to_s
      end
      nil
    end

    def parse_md5_cache_file(path)
      parse_md5_cache(File.read(path))
    rescue
      {}
    end

    def parse_md5_cache(content)
      h = {}

      content.each_line do |line|
        line = line.chomp
        next if line.blank?

        k, v = line.split("=", 2)
        h[k] = v if k.present?
      end

      h
    end

    def split_package_version(pf)
      parts = pf.split("-")
      return [nil, nil] if parts.length < 2

      (1...parts.length).each do |i|
        pn = parts[0...i].join("-")
        pv = parts[i..].join("-")
        return [pn, pv] if valid_pv?(pv)
      end

      [nil, nil]
    end

    def valid_pv?(pv)
      return false if pv.blank?

      return true if pv == "9999"

      !!(pv =~ /\A\d/)
    end

    def dep_atoms_from_field(str)
      return [] if str.blank?

      str.scan(ATOM_RE).flatten.map { |atom| normalize_dep_atom(atom) }.compact.uniq
    end

    def normalize_dep_atom(atom)
      s = atom.strip
      s = s.gsub(/\[[^\]]*\]/, "")
      s = s.sub(/:.*/, "")
      s.presence
    end

    def deps_from_field(field, kind)
      dep_atoms_from_field(field).map do |atom|
        {
          package_name: atom,
          requirements: "*",
          kind: kind,
          ecosystem: self.class.name.demodulize.downcase,
        }
      end
    end
  end
end
