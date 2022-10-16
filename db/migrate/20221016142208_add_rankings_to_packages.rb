class AddRankingsToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :rankings, :json, default: {}
  end
end
