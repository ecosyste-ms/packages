json.array! @versions do |version|
  package = version.package

  json.partial! 'api/v1/versions/version', version: version

  json.package do
    json.partial! 'api/v1/packages/package', package: package

    json.registry do
      json.partial! 'api/v1/registries/registry', registry: package.registry
    end
  end
end
