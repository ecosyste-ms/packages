class AddLastSyncedAtIndexToPackages < ActiveRecord::Migration[7.0]
  def change
    add_index :packages, [:status, :last_synced_at]
  end
end
