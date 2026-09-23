json.purl result.purl
json.match_status result.match_status

if result.version
  version = result.version
  package = version.package
  artifact = { download_url: version.download_url, integrity: version.integrity }.compact

  json.version do
    json.name package.name
    json.version version.number
    json.purl version.purl
    json.license_expression version.licenses.presence || package.licenses
    json.identifiers({ purl: version.purl, integrity: version.integrity }.compact)
    json.artifacts artifact.present? ? [artifact] : []
    json.dependencies version.dependencies do |dependency|
      json.partial! "api/v1/dependencies/dependency", dependency: dependency
    end
  end
end
