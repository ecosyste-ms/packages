class AddMaintainerIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :maintainers, [:registry_id, :login]
    add_index :maintainers, [:registry_id, :uuid], unique: true

    add_index :maintainerships, :maintainer_id
    add_index :maintainerships, :package_id
  end
end
