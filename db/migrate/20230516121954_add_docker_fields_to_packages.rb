class AddDockerFieldsToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :docker_dependents_count, :integer
    add_column :packages, :docker_downloads_count, :bigint
  end
end
