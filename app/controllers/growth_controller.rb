class GrowthController < ApplicationController
  def index
    @registries = Registry.all.sort_by { |r| -r.packages_count }
    @stats_by_registry = RegistryGrowthStat.from_min_year.includes(:registry).group_by(&:registry_id)

    # Aggregate stats across all registries by year
    @combined_stats = RegistryGrowthStat
      .from_min_year
      .group(:year)
      .select(
        :year,
        'SUM(packages_count) as packages_count',
        'SUM(versions_count) as versions_count',
        'SUM(new_packages_count) as new_packages_count',
        'SUM(new_versions_count) as new_versions_count'
      )
      .order(:year)
  end

  def show
    @registry = Registry.find_by_name!(params[:id])
    @stats = @registry.registry_growth_stats.from_min_year.by_year
  end

  def export
    if params[:id].present?
      export_registry
    else
      export_combined
    end
  end

  def export_registry
    registry = Registry.find_by_name!(params[:id])
    stats = registry.registry_growth_stats.from_min_year.by_year

    csv_data = CSV.generate do |csv|
      csv << ['year', 'packages_count', 'versions_count', 'new_packages_count', 'new_versions_count', 'packages_growth_rate', 'versions_growth_rate']
      stats.each do |stat|
        csv << [stat.year, stat.packages_count, stat.versions_count, stat.new_packages_count, stat.new_versions_count, stat.packages_growth_rate, stat.versions_growth_rate]
      end
    end

    send_data csv_data, filename: "growth-#{registry.name}.csv", type: 'text/csv'
  end

  def export_combined
    stats = RegistryGrowthStat
      .from_min_year
      .group(:year)
      .select(
        :year,
        'SUM(packages_count) as packages_count',
        'SUM(versions_count) as versions_count',
        'SUM(new_packages_count) as new_packages_count',
        'SUM(new_versions_count) as new_versions_count'
      )
      .order(:year)

    csv_data = CSV.generate do |csv|
      csv << ['year', 'packages_count', 'versions_count', 'new_packages_count', 'new_versions_count']
      stats.each do |stat|
        csv << [stat.year, stat.packages_count, stat.versions_count, stat.new_packages_count, stat.new_versions_count]
      end
    end

    send_data csv_data, filename: 'growth-combined.csv', type: 'text/csv'
  end
end
