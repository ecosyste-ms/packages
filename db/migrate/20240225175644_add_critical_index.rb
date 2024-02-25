class AddCriticalIndex < ActiveRecord::Migration[7.1]
  def change
    add_index :packages, :critical, where: "critical = true"
  end
end
