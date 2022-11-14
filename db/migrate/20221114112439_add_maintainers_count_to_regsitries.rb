class AddMaintainersCountToRegsitries < ActiveRecord::Migration[7.0]
  def change
    add_column :registries, :maintainers_count, :integer, default: 0
  end
end
