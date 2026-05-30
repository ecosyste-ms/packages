class AddDescNullsLastIndexToPackagesDependentReposCount < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :packages, [:registry_id, :dependent_repos_count],
              order: { dependent_repos_count: 'DESC NULLS LAST' },
              algorithm: :concurrently,
              name: 'index_packages_registry_id_dep_repos_desc'
  end
end
