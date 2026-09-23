class PurlVersionLookup
  Result = Data.define(:purl, :match_status, :version)

  def initialize(purl_string)
    @purl_string = purl_string.to_s
  end

  def call
    @purl = Purl.parse(@purl_string.gsub("npm/@", "npm/%40"))
    versions = matching_versions(package_scope)

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

    ecosystem = Ecosystem::Base.purl_type_to_ecosystem(@purl.type)
    separator = Ecosystem::Base.purl_type_to_namespace_separator(@purl.type)
    return Package.none if ecosystem.blank? || separator.nil?

    name = [namespace, @purl.name].compact.join(separator)
    registry_ids = matching_registry_ids(ecosystem)
    Package.where(name: name, registry_id: registry_ids)
  end

  def matching_registry_ids(ecosystem)
    repository_url = @purl.qualifiers&.fetch("repository_url", nil)
    registries = Registry.where(ecosystem: ecosystem)

    if repository_url.present?
      target_url = normalize_url(repository_url)
      registries.select { |registry| normalize_url(registry.url) == target_url }.map(&:id)
    else
      registries.pluck(:id)
    end
  end

  def matching_versions(packages)
    versions = if @purl.version.present?
      Version.where(package: packages).where("LOWER(versions.number) = ?", @purl.version.downcase)
    else
      latest_versions_for(packages)
    end

    versions.includes(:dependencies, package: :registry).order(:id).to_a
  end

  def latest_versions_for(packages)
    marked_versions = Version.where(package: packages, latest: true).active
    missing_package_ids = packages.where.not(id: marked_versions.select(:package_id)).pluck(:id)
    return marked_versions if missing_package_ids.empty?

    fallback_version_ids = Package.where(id: missing_package_ids).preload(:versions).filter_map do |package|
      latest_version_id_for(package.versions.to_a)
    end

    Version.where(id: marked_versions.select(:id)).or(Version.where(id: fallback_version_ids))
  end

  def latest_version_id_for(versions)
    active_versions = versions.select { |version| version.status.nil? }
    (active_versions.select(&:stable?).sort.first || active_versions.sort.first)&.id
  end

  def normalize_url(url)
    url.to_s.downcase.sub(%r{/+$}, "")
  end

  def result(match_status, version = nil)
    Result.new(purl: @purl_string, match_status: match_status, version: version)
  end
end
