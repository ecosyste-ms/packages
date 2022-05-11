class AddMetadataToVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :versions, :metadata, :json, default: {}
  end
end
