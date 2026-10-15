module VersionAdvisories
  extend ActiveSupport::Concern

  VERS_SCHEMES = {
    "go" => "golang",
    "packagist" => "composer",
    "rubygems" => "gem"
  }.freeze

  def version_scoped_advisories
    Array(package.advisories).filter_map do |advisory|
      advisory_for_version(advisory)
    end
  end

  private

  def advisory_for_version(advisory)
    affected_entries = matching_advisory_packages(advisory).select do |advisory_package|
      advisory_package_affected?(advisory_package)
    end
    return if affected_entries.empty?

    {
      "uuid" => advisory["uuid"],
      "identifiers" => Array(advisory["identifiers"]),
      "url" => advisory["url"],
      "title" => advisory["title"],
      "severity" => advisory["severity"],
      "affected" => true,
      "fixed" => false,
      "fixed_versions" => affected_entries.flat_map do |advisory_package|
        Array(advisory_package["versions"]).filter_map { |range| range["first_patched_version"].presence }
      end.uniq
    }.compact
  end

  def matching_advisory_packages(advisory)
    Array(advisory["packages"]).select do |advisory_package|
      advisory_package["ecosystem"].to_s.casecmp?(package.ecosystem.to_s) &&
        advisory_package["package_name"].to_s.casecmp?(package.name.to_s)
    end
  end

  def advisory_package_affected?(advisory_package)
    Array(advisory_package["versions"]).any? do |range|
      vulnerable_version_range?(range["vulnerable_version_range"])
    end
  end

  def vulnerable_version_range?(range)
    return false if range.blank?

    if package.ecosystem == "packagist"
      SemanticRange.satisfies?(number, range)
    else
      Vers.satisfies?(number, range, vers_scheme)
    end
  rescue ArgumentError
    false
  end

  def vers_scheme
    VERS_SCHEMES.fetch(package.ecosystem.downcase, package.ecosystem.downcase)
  end
end
