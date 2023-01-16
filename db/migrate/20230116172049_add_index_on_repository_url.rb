class AddIndexOnRepositoryUrl < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, :repository_url
  end
end
