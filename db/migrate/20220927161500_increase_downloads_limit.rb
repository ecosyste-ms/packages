class IncreaseDownloadsLimit < ActiveRecord::Migration[7.0]
  def change
    change_column :packages, :downloads, :bigint
  end
end
