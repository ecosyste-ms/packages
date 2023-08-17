class AddIssueMetadataToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :issue_metadata, :json
  end
end
