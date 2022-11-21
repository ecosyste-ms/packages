class AddNamespacesCountToRegistries < ActiveRecord::Migration[7.0]
  def change
    add_column :registries, :namespaces_count, :integer, default: 0
  end
end
