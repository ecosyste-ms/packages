class AddVersionToRegistries < ActiveRecord::Migration[7.0]
  def change
    add_column :registries, :version, :string
  end
end
