class AddMaintainersCountToPackages < ActiveRecord::Migration[7.0]
  def change
    add_column :packages, :maintainers_count, :integer, default: 0
  end
end
