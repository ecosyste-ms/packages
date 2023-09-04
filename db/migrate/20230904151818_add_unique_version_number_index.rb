class AddUniqueVersionNumberIndex < ActiveRecord::Migration[7.0]
  disable_ddl_transaction! 

  def change
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    add_index :versions, [:package_id, :number], unique: true, algorithm: :concurrently
  end
end
