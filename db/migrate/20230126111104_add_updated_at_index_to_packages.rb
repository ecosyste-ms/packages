class AddUpdatedAtIndexToPackages < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, [:registry_id, :updated_at]
  end
end
