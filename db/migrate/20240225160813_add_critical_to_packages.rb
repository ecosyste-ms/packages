class AddCriticalToPackages < ActiveRecord::Migration[7.1]
  def change
    add_column :packages, :critical, :boolean
  end
end
