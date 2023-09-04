class AddUniqueVersionNumberIndex < ActiveRecord::Migration[7.0]
  def change
    add_index :versions, [:package_id, :number], unique: true
  end
end
