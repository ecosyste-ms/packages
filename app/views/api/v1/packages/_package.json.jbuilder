json.extract! package, :name, :ecosystem, :description, :homepage, :licenses, :repository_url, :keywords_array, :versions_count, :latest_release_published_at, :latest_release_number, :last_synced_at, :created_at, :updated_at, :registry_url, :install_command, :documentation_url, :metadata, :repo_metadata, :repo_metadata_updated_at, :dependent_packages_count, :downloads, :downloads_period, :dependent_repos_count, :rankings

json.versions_url api_v1_registry_package_versions_url(registry_id: @registry.name, package_id: package.name)

json.maintainers package.maintainers, partial: 'api/v1/maintainers/maintainer', as: :maintainer