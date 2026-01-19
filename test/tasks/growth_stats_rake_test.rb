require 'test_helper'
require 'rake'

class GrowthStatsRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings do
        Packages::Application.load_tasks
      end
    end

    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')

    # Create packages with different creation dates
    @registry.packages.create!(
      name: 'package-2022',
      ecosystem: 'rubygems',
      first_release_published_at: Date.new(2022, 6, 15)
    )
    @registry.packages.create!(
      name: 'package-2023',
      ecosystem: 'rubygems',
      first_release_published_at: Date.new(2023, 3, 10)
    )

    # Re-enable the task so it can run again (Rake tasks only run once by default)
    Rake::Task["growth_stats:calculate"].reenable
  end

  test "calculate task creates growth stats for all registries" do
    # Creates stats from earliest package year (2022) to current year
    Rake::Task["growth_stats:calculate"].invoke
    assert @registry.registry_growth_stats.count >= 2
    assert @registry.registry_growth_stats.find_by(year: 2022).present?
    assert @registry.registry_growth_stats.find_by(year: 2023).present?
  end

  test "calculate task populates package counts correctly" do
    Rake::Task["growth_stats:calculate"].invoke

    stat_2022 = @registry.registry_growth_stats.find_by(year: 2022)
    stat_2023 = @registry.registry_growth_stats.find_by(year: 2023)

    assert_equal 1, stat_2022.packages_count
    assert_equal 1, stat_2022.new_packages_count

    assert_equal 2, stat_2023.packages_count
    assert_equal 1, stat_2023.new_packages_count
  end
end
