class AddKeywordsCountToRegistries < ActiveRecord::Migration[7.0]
  def change
    add_column :registries, :keywords_count, :integer, default: 0
  end
end
