class AddBinaryNamesIndexToPackages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = 'index_packages_on_binary_names'

  # Lets purl lookups find the Debian or Ubuntu source package that builds a binary package
  def up
    ActiveRecord::Base.connection.execute('SET statement_timeout TO 0')
    # A failed concurrent build leaves an invalid index behind, which if_not_exists would otherwise accept
    remove_index :packages, name: INDEX_NAME, algorithm: :concurrently if invalid_index?
    add_index :packages, "regexp_split_to_array((metadata ->> 'binary'), '\\s*,\\s*')",
              using: :gin,
              name: INDEX_NAME,
              where: "(metadata ->> 'binary') IS NOT NULL",
              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :packages, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  private

  def invalid_index?
    select_value(<<~SQL) == false
      SELECT pg_index.indisvalid FROM pg_index
      JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(INDEX_NAME)}
    SQL
  end
end
