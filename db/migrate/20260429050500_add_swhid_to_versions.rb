class AddSwhidToVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :versions, :swhid, :string
    add_index :versions, :swhid, unique: true, where: "swhid IS NOT NULL"
  end
end
