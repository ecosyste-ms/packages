class CreateArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :artifacts do |t|
      t.references :version, null: false, type: :bigint,
                             foreign_key: { on_delete: :cascade }, index: false
      t.string :identifier, null: false
      t.string :filename
      t.string :kind
      t.text :download_url
      t.bigint :size
      t.datetime :published_at
      t.string :status
      t.string :integrity
      t.jsonb :metadata
      t.timestamps
    end

    add_index :artifacts, :version_id
    add_index :artifacts, [:version_id, :identifier], unique: true
    add_index :artifacts, :integrity, using: :hash, where: "integrity IS NOT NULL"
  end
end
