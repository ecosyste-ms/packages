class AddUpstreamRepositoryUrlIndexToPackages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    add_index :packages, "lower(metadata ->> 'upstream_repository_url')",
              name: 'index_packages_on_lower_upstream_repository_url',
              where: "(metadata ->> 'upstream_repository_url') IS NOT NULL",
              algorithm: :concurrently, if_not_exists: true
  end
end
