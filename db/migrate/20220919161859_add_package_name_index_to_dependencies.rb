class AddPackageNameIndexToDependencies < ActiveRecord::Migration[7.0]
  def change
    add_index :dependencies, [:ecosystem, :package_name]
  end
end
