class AddCompoundIndexToVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    add_index :versions, [:registry_id, :published_at], algorithm: :concurrently, if_not_exists: true
    add_index :versions, [:registry_id, :created_at], algorithm: :concurrently, if_not_exists: true
    remove_index :versions, :registry_id, algorithm: :concurrently, if_exists: true
  end
end
