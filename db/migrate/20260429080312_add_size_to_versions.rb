class AddSizeToVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :versions, :size, :bigint
  end
end
