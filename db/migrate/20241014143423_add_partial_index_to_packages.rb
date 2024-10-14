class AddPartialIndexToPackages < ActiveRecord::Migration[7.2]
  def change
    execute <<-SQL
      CREATE INDEX index_packages_on_registry_id_and_normalized_name
      ON packages (registry_id, (metadata->>'normalized_name'))
      WHERE (metadata->>'normalized_name') IS NOT NULL;
    SQL
  end
end