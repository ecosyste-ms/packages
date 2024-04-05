class AddOrganizationToMaintainers < ActiveRecord::Migration[7.1]
  def change
    add_column :maintainers, :organization, :boolean
  end
end
