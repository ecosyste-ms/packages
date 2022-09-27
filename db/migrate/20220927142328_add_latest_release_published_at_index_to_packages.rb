class AddLatestReleasePublishedAtIndexToPackages < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, :latest_release_published_at
  end
end
