class AddTotalDownloadsToMaintainers < ActiveRecord::Migration[7.1]
  def change
    add_column :maintainers, :total_downloads, :bigint
  end
end
