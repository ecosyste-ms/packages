if maintainership.maintainer.present?
  json.extract! maintainership.maintainer, :uuid, :login, :name, :email, :url, :packages_count, :html_url
  json.extract! maintainership, :role, :created_at, :updated_at
  json.packages_url packages_api_v1_registry_maintainer_url(registry_id: maintainership.maintainer.registry.name, id: maintainership.maintainer.to_param)
end