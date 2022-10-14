class AddDependentReposCountToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :dependent_repos_count, :integer, default: 0
  end
end
