json.array! @packages do |package|
  json.extract! package, :name, :ecosystem, :description, :homepage, :licenses, :normalized_licenses, :repository_url, :keywords_array, :namespace, :versions_count, :first_release_published_at, :latest_release_published_at, :latest_release_number, :last_synced_at, :created_at, :updated_at, :registry_url, :install_command, :documentation_url, :metadata, :repo_metadata, :repo_metadata_updated_at, :dependent_packages_count, :downloads, :downloads_period, :dependent_repos_count, :rankings, :purl, :advisories, :docker_usage_url, :docker_dependents_count, :docker_downloads_count, :usage_url, :dependent_repositories_url

  json.versions_url api_v1_registry_package_versions_url(registry_id: package.registry.name, package_id: package.name)
  json.dependent_packages_url dependent_packages_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)
  json.related_packages_url related_packages_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)

  json.maintainers package.maintainerships.select{|m| m.maintainer.present? } do |maintainership|
    json.extract! maintainership.maintainer, :uuid, :login, :name, :email, :url, :packages_count, :html_url
    json.extract! maintainership, :role, :created_at, :updated_at
    json.packages_url packages_api_v1_registry_maintainer_url(registry_id: maintainership.maintainer.registry.name, id: maintainership.maintainer.to_param)
  end

  json.registry do
    json.extract!package.registry, :name, :url, :ecosystem, :default, :packages_count, :maintainers_count, :namespaces_count, :keywords_count, :github, :metadata, :icon_url, :created_at, :updated_at
    json.packages_url api_v1_registry_packages_url(registry_id:package.registry.name)
    json.maintainers_url api_v1_registry_maintainers_url(registry_id:package.registry.name)
    json.namespaces_url api_v1_registry_namespaces_url(registry_id:package.registry.name)
  end
end