class AddMetadataToRegistries < ActiveRecord::Migration[7.0]
  def change
    add_column :registries, :metadata, :json, default: {}
  end
end
