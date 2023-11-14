class AddRegistryIdToVersions < ActiveRecord::Migration[7.1]
  def change
    add_column :versions, :registry_id, :integer
    add_index :versions, :registry_id
  end
end
