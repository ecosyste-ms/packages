require "test_helper"

class RegistryGrowthStatTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:registry)
  end

  context 'validations' do
    should validate_presence_of(:registry_id)
    should validate_presence_of(:year)
  end

  setup do
    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
  end

  test 'uniqueness of year scoped to registry' do
    RegistryGrowthStat.create!(registry: @registry, year: 2023, packages_count: 100, versions_count: 500)
    duplicate = RegistryGrowthStat.new(registry: @registry, year: 2023, packages_count: 150, versions_count: 600)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:year], 'has already been taken'
  end

  test 'allows same year for different registries' do
    other_registry = Registry.create(name: 'npmjs.org', url: 'https://npmjs.org', ecosystem: 'npm')
    RegistryGrowthStat.create!(registry: @registry, year: 2023, packages_count: 100, versions_count: 500)
    stat = RegistryGrowthStat.new(registry: other_registry, year: 2023, packages_count: 200, versions_count: 1000)
    assert stat.valid?
  end

  test 'by_year scope orders by year ascending' do
    RegistryGrowthStat.create!(registry: @registry, year: 2023, packages_count: 300)
    RegistryGrowthStat.create!(registry: @registry, year: 2021, packages_count: 100)
    RegistryGrowthStat.create!(registry: @registry, year: 2022, packages_count: 200)

    years = @registry.registry_growth_stats.by_year.pluck(:year)
    assert_equal [2021, 2022, 2023], years
  end

  test 'packages_growth_rate calculates percentage growth' do
    RegistryGrowthStat.create!(registry: @registry, year: 2022, packages_count: 100)
    stat_2023 = RegistryGrowthStat.create!(registry: @registry, year: 2023, packages_count: 150)

    assert_equal 50.0, stat_2023.packages_growth_rate
  end

  test 'packages_growth_rate returns nil for first year' do
    stat = RegistryGrowthStat.create!(registry: @registry, year: 2022, packages_count: 100)
    assert_nil stat.packages_growth_rate
  end

  test 'packages_growth_rate returns nil when previous count is zero' do
    RegistryGrowthStat.create!(registry: @registry, year: 2022, packages_count: 0)
    stat_2023 = RegistryGrowthStat.create!(registry: @registry, year: 2023, packages_count: 100)

    assert_nil stat_2023.packages_growth_rate
  end

  test 'versions_growth_rate calculates percentage growth' do
    RegistryGrowthStat.create!(registry: @registry, year: 2022, versions_count: 1000)
    stat_2023 = RegistryGrowthStat.create!(registry: @registry, year: 2023, versions_count: 1500)

    assert_equal 50.0, stat_2023.versions_growth_rate
  end

  test 'versions_growth_rate returns nil for first year' do
    stat = RegistryGrowthStat.create!(registry: @registry, year: 2022, versions_count: 1000)
    assert_nil stat.versions_growth_rate
  end

  test 'default values for counts' do
    stat = RegistryGrowthStat.create!(registry: @registry, year: 2023)
    assert_equal 0, stat.packages_count
    assert_equal 0, stat.versions_count
    assert_equal 0, stat.new_packages_count
    assert_equal 0, stat.new_versions_count
  end

  test 'previous_stat finds stat from previous year' do
    stat_2022 = RegistryGrowthStat.create!(registry: @registry, year: 2022, packages_count: 100)
    stat_2023 = RegistryGrowthStat.create!(registry: @registry, year: 2023, packages_count: 150)

    assert_equal stat_2022, stat_2023.previous_stat
  end

  test 'previous_stat returns nil when no previous year exists' do
    stat = RegistryGrowthStat.create!(registry: @registry, year: 2022)
    assert_nil stat.previous_stat
  end
end
