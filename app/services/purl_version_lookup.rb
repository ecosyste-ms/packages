class PurlVersionLookup
  Result = Data.define(:purl, :match_status, :version)

  BINARY_NAMES_SQL = "regexp_split_to_array((packages.metadata ->> 'binary'), '\\s*,\\s*')".freeze

  def initialize(purl_string)
    @purl_string = purl_string.to_s
  end

  def call
    @purl = Purl.parse(@purl_string.gsub("npm/@", "npm/%40"))
    versions = matching_versions(package_scope)
    versions = deb_binary_versions if versions.empty? && deb_binary_lookup?

    if versions.empty?
      result("missing")
    elsif versions.one?
      result("matched", versions.first)
    else
      result("ambiguous")
    end
  rescue ArgumentError, Purl::Error
    result("missing")
  end

  private

  def package_scope
    namespace = @purl.type == "docker" && @purl.namespace.nil? ? "library" : @purl.namespace

    if @purl.type == "github"
      return Package.repository_url("https://github.com/#{@purl.namespace}/#{@purl.name}")
    end

    resolver = PurlLookupResolver.new(@purl)
    ecosystem = resolver.ecosystem
    name = resolver.package_name(namespace: namespace)
    return Package.none if ecosystem.blank? || name.nil?

    scope = Package.where(registry_id: resolver.registry_ids)
    scope.with_ecosystem_name(name, ecosystem)
  end

  def matching_versions(packages)
    versions = if @purl.type == "oci"
      oci_versions(packages)
    elsif @purl.version.present?
      Version.where(package: packages).where("LOWER(versions.number) = ?", @purl.version.downcase)
    else
      latest_versions_for(packages)
    end

    versions.includes(:dependencies, package: :registry).order(:id).to_a
  end

  # An oci purl carries the manifest digest as its version and the tag as a qualifier
  def oci_versions(packages)
    tag = @purl.qualifiers.to_h["tag"]
    return latest_versions_for(packages) if @purl.version.blank? && tag.blank?

    versions = Version.where(package: packages)
    versions = versions.where("versions.metadata->>'digest' = ?", @purl.version.downcase) if @purl.version.present?
    versions = versions.where(number: tag) if tag.present?
    versions
  end

  def latest_versions_for(packages)
    marked_versions = Version.where(package: packages, latest: true).active
    missing_package_ids = packages.where.not(id: marked_versions.select(:package_id)).pluck(:id)
    return marked_versions if missing_package_ids.empty?

    fallback_version_ids = Package.where(id: missing_package_ids).preload(:versions).filter_map do |package|
      package.latest_version_from(package.versions.to_a)&.id
    end

    Version.where(id: marked_versions.select(:id)).or(Version.where(id: fallback_version_ids))
  end

  # Debian and Ubuntu registries index source packages, while scanners report the binaries installed in an image.
  # arch=source names the source package itself, so there is no binary to resolve
  def deb_binary_lookup?
    @purl.type == "deb" && @purl.version.present? && @purl.qualifiers.to_h["arch"] != "source"
  end

  def deb_binary_versions
    resolver = PurlLookupResolver.new(@purl)
    return [] if resolver.ecosystem.blank?

    source_name, source_version = @purl.qualifiers.to_h["upstream"].to_s.split("@", 2)
    packages = Package.where(registry_id: resolver.registry_ids, ecosystem: resolver.ecosystem)
    packages = if source_name.present?
                 packages.where(name: source_name)
               else
                 # matches the expression of index_packages_on_binary_names, so the GIN index serves it
                 packages.where("(packages.metadata->>'binary') IS NOT NULL")
                         .where("#{BINARY_NAMES_SQL} @> ARRAY[?]::text[]", @purl.name)
               end

    # a source version in upstream says exactly which source version the binary came from
    numbers = source_version.present? ? [source_version] : [@purl.version, without_binnmu(@purl.version)]
    numbers = numbers.map(&:downcase).uniq
    Version.where(package: packages).where("LOWER(versions.number) IN (?)", numbers)
           .includes(:dependencies, package: :registry).order(:id).to_a
  end

  # A binNMU rebuilds the binaries without a source change and adds +bN to their version (3.0.11-1~deb12u1+b1)
  def without_binnmu(version)
    version.sub(/\+b\d+\z/, "")
  end

  def result(match_status, version = nil)
    Result.new(purl: @purl_string, match_status: match_status, version: version)
  end
end
