class CreateRegistryGrowthStats < ActiveRecord::Migration[8.1]
  def change
    create_table :registry_growth_stats do |t|
      t.references :registry, null: false, foreign_key: true
      t.integer :year, null: false
      t.bigint :packages_count, default: 0
      t.bigint :versions_count, default: 0
      t.bigint :new_packages_count, default: 0
      t.bigint :new_versions_count, default: 0

      t.timestamps
    end

    add_index :registry_growth_stats, [:registry_id, :year], unique: true
  end
end
