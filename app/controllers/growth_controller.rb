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
end
