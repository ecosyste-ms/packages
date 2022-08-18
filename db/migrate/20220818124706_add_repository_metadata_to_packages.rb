class AddRepositoryMetadataToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :repo_metadata, :json, default: {}
    add_column :packages, :repo_metadata_updated_at, :datetime
  end
end
