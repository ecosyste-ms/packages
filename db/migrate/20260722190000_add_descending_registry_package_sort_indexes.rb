class AddDescendingRegistryPackageSortIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')

    add_index :packages,
              'registry_id, downloads DESC NULLS LAST',
              name: 'index_packages_on_registry_downloads_desc',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :packages,
              'registry_id, dependent_packages_count DESC NULLS LAST',
              name: 'index_packages_on_registry_dependent_packages_desc',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :packages,
              'registry_id, dependent_repos_count DESC NULLS LAST',
              name: 'index_packages_on_registry_dependent_repos_desc',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :packages,
              "registry_id, ((repo_metadata ->> 'stargazers_count')::text::integer) DESC NULLS LAST",
              name: 'index_packages_on_registry_stargazers_desc',
              algorithm: :concurrently,
              if_not_exists: true
    add_index :packages,
              "registry_id, ((repo_metadata ->> 'forks_count')::text::integer) DESC NULLS LAST",
              name: 'index_packages_on_registry_forks_desc',
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :packages,
                 name: 'index_packages_on_registry_downloads_desc',
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :packages,
                 name: 'index_packages_on_registry_dependent_packages_desc',
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :packages,
                 name: 'index_packages_on_registry_dependent_repos_desc',
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :packages,
                 name: 'index_packages_on_registry_stargazers_desc',
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :packages,
                 name: 'index_packages_on_registry_forks_desc',
                 algorithm: :concurrently,
                 if_exists: true
  end
end
