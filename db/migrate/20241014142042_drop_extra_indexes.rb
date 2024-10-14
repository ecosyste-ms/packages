class DropExtraIndexes < ActiveRecord::Migration[7.2]
  def change
    remove_index :maintainerships, :package_id
    remove_index :versions, :package_id
  end
end
