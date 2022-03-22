class CreateDependencies < ActiveRecord::Migration[7.0]
  def change
    create_table :dependencies do |t|
      t.integer :package_id
      t.integer :version_id
      t.string :package_name
      t.string :ecosystem
      t.string :kind
      t.boolean :optional, default: false
      t.string :requirements

      t.timestamps
    end
  end
end
