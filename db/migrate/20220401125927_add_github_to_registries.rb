class AddGithubToRegistries < ActiveRecord::Migration[7.0]
  def change
    add_column :registries, :github, :string
  end
end
