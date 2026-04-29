class AddSizeToVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :versions, :size, :bigint
    add_index :versions, :size
  end
end
