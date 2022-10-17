class AddIndexesToPackages < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, :downloads
    add_index :packages, :dependent_packages_count
    add_index :packages, :dependent_repos_count
  end
end
