json.extract! version, :id, :number, :published_at, :licenses, :integrity, :status, :download_url, :registry_url, :documentation_url, :install_command, :metadata, :created_at, :updated_at, :purl, :related_tag, :latest
json.version_url api_v1_registry_package_version_url(version.package.registry, version.package, version)
json.codemeta_url codemeta_api_v1_registry_package_version_url(version.package.registry, version.package, version)
json.dependencies version.dependencies do |dependency|
  json.extract! dependency, :id, :ecosystem, :package_name, :requirements, :kind, :optional
end