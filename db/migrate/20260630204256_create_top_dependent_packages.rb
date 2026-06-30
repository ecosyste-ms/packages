class CreateTopDependentPackages < ActiveRecord::Migration[8.1]
  def change
    create_table :top_dependent_packages do |t|
      t.integer :package_id, null: false
      t.string :sort, null: false
      t.integer :dependent_ids, array: true, null: false, default: []
      t.datetime :updated_at, null: false
    end
    add_index :top_dependent_packages, [:package_id, :sort], unique: true
  end
end
