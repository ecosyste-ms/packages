class AddVersionsIndex < ActiveRecord::Migration[7.0]
  def change
    add_index :versions, :published_at
  end
end
