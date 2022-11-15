class AddNamespaceToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :namespace, :string
    add_index :packages, [:registry_id, :namespace]
  end
end
