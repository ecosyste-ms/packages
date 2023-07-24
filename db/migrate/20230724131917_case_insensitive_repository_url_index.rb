class CaseInsensitiveRepositoryUrlIndex < ActiveRecord::Migration[7.0]
  def change
    remove_index :packages, :repository_url
    add_index :packages, "lower(repository_url)"
  end
end
