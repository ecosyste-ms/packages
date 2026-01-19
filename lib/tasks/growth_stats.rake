namespace :growth_stats do
  desc "Calculate and cache year-over-year growth stats for all registries (skips existing data, use FORCE=1 to recalculate)"
  task calculate: :environment do
    force = ENV["FORCE"] == "1"
    puts "Calculating growth stats for all registries#{force ? ' (forcing recalculation)' : ' (skipping existing)'}..."

    Registry.order(:packages_count).each do |registry|
      puts "Processing registry: #{registry.name} (#{registry.packages_count} packages)"
      registry.calculate_growth_stats(force: force) do |year, status, stat|
        if status == :skipped
          puts "  #{year}: skipped (already calculated)"
        else
          puts "  #{year}: #{stat.packages_count} packages (#{stat.new_packages_count} new), #{stat.versions_count} versions (#{stat.new_versions_count} new)"
        end
      end
    end

    puts "Finished calculating growth stats"
  end

  desc "Calculate growth stats for a specific registry (use FORCE=1 to recalculate existing)"
  task :calculate_for, [:registry_name] => :environment do |_t, args|
    registry = Registry.find_by_name!(args[:registry_name])
    force = ENV["FORCE"] == "1"

    puts "Processing registry: #{registry.name}#{force ? ' (forcing recalculation)' : ''}"
    registry.calculate_growth_stats(force: force) do |year, status, stat|
      if status == :skipped
        puts "  #{year}: skipped (already calculated)"
      else
        puts "  #{year}: #{stat.packages_count} packages (#{stat.new_packages_count} new), #{stat.versions_count} versions (#{stat.new_versions_count} new)"
      end
    end
    puts "Finished"
  end
end
