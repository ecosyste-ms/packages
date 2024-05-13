class AddLatestToVersions < ActiveRecord::Migration[7.1]
  def change
    add_column :versions, :latest, :boolean
  end
end
