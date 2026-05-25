json.array! @packages do |package|
  json.partial! 'api/v1/packages/package', package: package

  if @lookup_versions_by_package_id.present? && @lookup_versions_by_package_id[package.id].present?
    json.published_at @lookup_versions_by_package_id[package.id].published_at
  end

  json.registry do
    json.extract!package.registry, :name, :url, :ecosystem, :default, :packages_count, :maintainers_count, :namespaces_count, :keywords_count, :github, :metadata, :icon_url, :created_at, :updated_at
    json.packages_url api_v1_registry_packages_url(registry_id:package.registry.name)
    json.maintainers_url api_v1_registry_maintainers_url(registry_id:package.registry.name)
    json.namespaces_url api_v1_registry_namespaces_url(registry_id:package.registry.name)
  end
end