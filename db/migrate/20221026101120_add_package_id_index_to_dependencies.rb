class AddPackageIdIndexToDependencies < ActiveRecord::Migration[7.0]
  def change
    add_index :dependencies, :package_id
  end
end
