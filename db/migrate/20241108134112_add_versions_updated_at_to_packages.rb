class AddVersionsUpdatedAtToPackages < ActiveRecord::Migration[7.2]
  def change
    add_column :packages, :versions_updated_at, :datetime
  end
end
