class CreateMaintainerships < ActiveRecord::Migration[7.0]
  def change
    create_table :maintainerships do |t|
      t.integer :package_id
      t.integer :maintainer_id
      t.string :role

      t.timestamps
    end
  end
end
