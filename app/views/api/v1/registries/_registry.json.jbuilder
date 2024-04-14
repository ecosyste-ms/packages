json.extract! registry, :name, :url, :ecosystem, :default, :packages_count, :versions_count, :maintainers_count, :namespaces_count, :keywords_count, :downloads, :github, :metadata, :icon_url, :purl_type, :created_at, :updated_at
json.packages_url api_v1_registry_packages_url(registry_id: registry.name)
json.maintainers_url api_v1_registry_maintainers_url(registry_id: registry.name)
json.namespaces_url api_v1_registry_namespaces_url(registry_id: registry.name)