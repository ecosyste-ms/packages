class SetDefaultStatusOnPackages < ActiveRecord::Migration[7.2]
  def change
    change_column_default :packages, :status, from: nil, to: 'active'
  end
end
