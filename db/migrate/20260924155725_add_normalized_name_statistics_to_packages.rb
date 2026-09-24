class AddNormalizedNameStatisticsToPackages < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE STATISTICS IF NOT EXISTS packages_normalized_name_stats ON (metadata->>'normalized_name') FROM packages"
  end

  def down
    execute "DROP STATISTICS IF EXISTS packages_normalized_name_stats"
  end
end
