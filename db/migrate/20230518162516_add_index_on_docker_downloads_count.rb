class AddIndexOnDockerDownloadsCount < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, [:registry_id, :docker_downloads_count]
  end
end
