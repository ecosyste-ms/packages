namespace :growth_stats do
  desc "Calculate and cache year-over-year growth stats for all registries"
  task calculate: :environment do
    puts "Calculating growth stats for all registries..."

    min_year = RegistryGrowthStat::MIN_YEAR
    end_year = Time.current.year

    puts "Calculating stats from #{min_year} to #{end_year}"

    Registry.find_each do |registry|
      puts "Processing registry: #{registry.name} (id: #{registry.id})"
      calculate_growth_stats_for_registry(registry, min_year, end_year)
    end

    puts "Finished calculating growth stats"
  end

  desc "Calculate growth stats for a specific registry"
  task :calculate_for, [:registry_name] => :environment do |_t, args|
    registry = Registry.find_by_name!(args[:registry_name])
    min_year = RegistryGrowthStat::MIN_YEAR
    end_year = Time.current.year

    puts "Processing registry: #{registry.name} (#{min_year} to #{end_year})"
    calculate_growth_stats_for_registry(registry, min_year, end_year)
    puts "Finished"
  end

  def calculate_growth_stats_for_registry(registry, start_year, end_year)
    (start_year..end_year).each do |year|
      year_end = Date.new(year, 12, 31).end_of_day

      # Use efficient SQL counts
      packages_count = registry.packages
        .where("COALESCE(first_release_published_at, created_at) <= ?", year_end)
        .count

      versions_count = registry.versions
        .where("COALESCE(published_at, created_at) <= ?", year_end)
        .count

      year_start = Date.new(year, 1, 1).beginning_of_day
      new_packages_count = registry.packages
        .where("COALESCE(first_release_published_at, created_at) >= ? AND COALESCE(first_release_published_at, created_at) <= ?", year_start, year_end)
        .count

      new_versions_count = registry.versions
        .where("COALESCE(published_at, created_at) >= ? AND COALESCE(published_at, created_at) <= ?", year_start, year_end)
        .count

      stat = RegistryGrowthStat.find_or_initialize_by(registry_id: registry.id, year: year)
      stat.update!(
        packages_count: packages_count,
        versions_count: versions_count,
        new_packages_count: new_packages_count,
        new_versions_count: new_versions_count
      )

      puts "  #{year}: #{packages_count} packages (#{new_packages_count} new), #{versions_count} versions (#{new_versions_count} new)"
    end
  end
end
