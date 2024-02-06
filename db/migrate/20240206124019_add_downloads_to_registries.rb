class AddDownloadsToRegistries < ActiveRecord::Migration[7.1]
  def change
    add_column :registries, :downloads, :bigint
  end
end
