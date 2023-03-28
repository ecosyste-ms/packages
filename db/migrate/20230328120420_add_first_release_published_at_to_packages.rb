class AddFirstReleasePublishedAtToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :first_release_published_at, :datetime
  end
end
