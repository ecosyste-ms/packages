json.extract! maintainership.maintainer, :uuid, :login, :name, :email, :url, :created_at, :updated_at, :packages_count
json.extract! maintainership, :role
json.packages_url packages_api_v1_registry_maintainer_url(registry_id: maintainership.maintainer.registry.name, id: maintainership.maintainer.to_param)