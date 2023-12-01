class AddVersionsCountToRegistries < ActiveRecord::Migration[7.1]
  def change
    add_column :registries, :versions_count, :integer
  end
end
