class AddBinaryNamesIndexToPackages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Lets purl lookups find the Debian or Ubuntu source package that builds a binary package
  def change
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    add_index :packages, "regexp_split_to_array((metadata ->> 'binary'), '\\s*,\\s*')",
              using: :gin,
              name: 'index_packages_on_binary_names',
              where: "(metadata ->> 'binary') IS NOT NULL",
              algorithm: :concurrently, if_not_exists: true
  end
end
