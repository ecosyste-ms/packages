class AddUniqueIndexToMaintainerships < ActiveRecord::Migration[7.1]
  def change
    add_index :maintainerships, [:package_id, :maintainer_id], unique: true
  end
end