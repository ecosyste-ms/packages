class AddDependentReposCountToRegistries < ActiveRecord::Migration[7.2]
  def change
    add_column :registries, :dependent_repos_count, :bigint, default: 0
  end
end
