class RepurposeKeywordsField < ActiveRecord::Migration[7.0]
  def change
    remove_column :packages, :keywords
    add_column :packages, :keywords, :string, array: true, default: []
  end
end
