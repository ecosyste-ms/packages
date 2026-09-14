json.array! @artifacts do |artifact|
  version = artifact.version

  json.partial! 'api/v1/artifacts/artifact', artifact: artifact
  json.version do
    json.partial! 'api/v1/versions/version', version: version

    json.package do
      json.partial! 'api/v1/packages/package', package: version.package

      json.registry do
        json.partial! 'api/v1/registries/registry', registry: version.package.registry
      end
    end
  end
end
