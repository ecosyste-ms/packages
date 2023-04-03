class AddKeywordsIndex < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, :keywords, using: :gin
  end
end
