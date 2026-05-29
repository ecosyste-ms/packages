class AddIntegrityIndexToVersions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :versions, :integrity, algorithm: :concurrently, where: "integrity IS NOT NULL"
  end
end
