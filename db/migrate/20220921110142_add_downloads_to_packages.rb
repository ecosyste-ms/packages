class AddDownloadsToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :downloads, :integer
    add_column :packages, :downloads_period, :string
  end
end
