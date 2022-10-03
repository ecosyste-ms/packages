json.extract! registry, :name, :url, :ecosystem, :default, :packages_count, :metadata, :created_at, :updated_at
json.packages_url api_v1_registry_packages_url(registry_id: registry.name)