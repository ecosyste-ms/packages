class AddVersionIndexToDependencies < ActiveRecord::Migration[7.0]
  def change
    add_index(:dependencies, :version_id)
  end
end
