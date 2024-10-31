class AddActivePackagesCountToRegistries < ActiveRecord::Migration[7.2]
  def change
    add_column :registries, :active_packages_count, :integer, default: 0
  end
end
