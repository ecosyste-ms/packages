class AddLatestPublishedReleaseNumberToPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :packages, :latest_published_release_number, :string
  end
end
