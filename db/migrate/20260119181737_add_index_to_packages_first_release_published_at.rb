class AddIndexToPackagesFirstReleasePublishedAt < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    add_index :packages, :first_release_published_at, algorithm: :concurrently
  end
end
