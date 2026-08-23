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
      version_ids = packages.filter_map { |package| package.latest_version&.id }
      Version.where(id: version_ids)
    end

    versions.includes(:dependencies, package: :registry).order(:id).to_a
  end

  def normalize_url(url)
    url.to_s.downcase.sub(%r{/+$}, "")
  end

  def result(match_status, version = nil)
    Result.new(purl: @purl_string, match_status: match_status, version: version)
  end
end
