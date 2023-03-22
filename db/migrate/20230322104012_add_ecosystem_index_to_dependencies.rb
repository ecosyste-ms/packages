class AddEcosystemIndexToDependencies < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!
  
  def change
    remove_index :dependencies, :package_name
    add_index :dependencies, [:ecosystem, :package_name], algorithm: :concurrently
  end
end
