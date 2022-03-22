class CreateVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :versions do |t|
      t.integer :package_id
      t.string :number
      t.datetime :published_at
      t.string :licenses
      t.string :integrity
      t.string :status

      t.timestamps
    end
  end
end
