json.extract! package, :name, :ecosystem, :description, :homepage, :licenses, :normalized_licenses, :repository_url, :keywords_array, :namespace, :versions_count, :first_release_published_at, :latest_release_published_at, :latest_release_number, :last_synced_at, :created_at, :updated_at, :registry_url, :install_command, :documentation_url, :metadata, :repo_metadata, :repo_metadata_updated_at, :dependent_packages_count, :downloads, :downloads_period, :dependent_repos_count, :rankings, :purl, :advisories, :docker_usage_url, :docker_dependents_count, :docker_downloads_count, :usage_url, :dependent_repositories_url

json.versions_url api_v1_registry_package_versions_url(registry_id: package.registry.name, package_id: package.name)
json.version_numbers_url version_numbers_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)
json.dependent_packages_url dependent_packages_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)
json.related_packages_url related_packages_api_v1_registry_package_url(registry_id: package.registry.name, id: package.name)

json.maintainers package.maintainerships.select{|m| m.maintainer.present? }, partial: 'api/v1/maintainerships/maintainership', as: :maintainership