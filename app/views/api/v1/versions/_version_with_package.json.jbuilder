json.extract! version, :id, :number, :published_at, :licenses, :integrity, :status, :download_url, :registry_url, :documentation_url, :install_command, :metadata, :created_at, :updated_at, :purl, :related_tag, :latest
json.version_url api_v1_registry_package_version_url(@registry, version.package, version.number)
json.package do
  json.partial! 'api/v1/packages/package', package: version.package
end

#json.dependencies version.dependencies, partial: 'api/v1/dependencies/dependency', as: :dependency