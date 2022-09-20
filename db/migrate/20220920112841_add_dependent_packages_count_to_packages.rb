class AddDependentPackagesCountToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :dependent_packages_count, :integer, default: 0
  end
end
