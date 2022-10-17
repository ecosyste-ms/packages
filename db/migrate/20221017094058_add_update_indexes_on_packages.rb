class AddUpdateIndexesOnPackages < ActiveRecord::Migration[7.0]
  def change
    remove_index :packages, :downloads
    remove_index :packages, :dependent_packages_count
    remove_index :packages, :dependent_repos_count

    add_index :packages, [:registry_id, :downloads]
    add_index :packages, [:registry_id, :dependent_packages_count]
    add_index :packages, [:registry_id, :dependent_repos_count]
  end
end
