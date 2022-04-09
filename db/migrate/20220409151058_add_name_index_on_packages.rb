class AddNameIndexOnPackages < ActiveRecord::Migration[7.0]
  def change
    remove_index :packages, :registry_id
    add_index :packages, [:registry_id, :name], unique: true
  end
end
