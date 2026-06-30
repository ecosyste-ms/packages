class AddLatestCoveringIndexToVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    add_index :versions, :id,
              include: [:package_id],
              where: "latest = true",
              name: "index_versions_on_id_where_latest_covering",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
