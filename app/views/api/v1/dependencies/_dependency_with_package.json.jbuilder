json.extract! dependency, :id, :ecosystem, :package_name, :requirements, :kind, :optional
if dependency.version&.package
  json.package do
    json.partial! 'api/v1/packages/package', package: dependency.version.package
  end
  json.version do
    json.partial! 'api/v1/versions/version', version: dependency.version
  end
else
  json.package nil
  json.version nil
end
