json.array! @packages do |package|
  json.partial! 'api/v1/packages/package', package: package
  json.registry do
    json.partial! 'api/v1/registries/registry', registry: package.registry
  end
end