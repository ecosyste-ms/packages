class UpdateDependencyIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index :dependencies, name: 'index_dependencies_on_ecosystem_and_package_name'
    add_index :dependencies, :package_name
  end
end
