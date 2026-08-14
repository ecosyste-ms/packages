class AddDownloadsUpdatedAtToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :downloads_updated_at, :datetime
  end
end
