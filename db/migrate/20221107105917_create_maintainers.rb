class CreateMaintainers < ActiveRecord::Migration[7.0]
  def change
    create_table :maintainers do |t|
      t.integer :registry_id
      t.string :uuid
      t.string :login
      t.string :email
      t.string :name
      t.string :url
      t.integer :packages_count, default: 0

      t.timestamps
    end
  end
end
