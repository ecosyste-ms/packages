require 'test_helper'

class GrowthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @stat_2022 = RegistryGrowthStat.create!(
      registry: @registry,
      year: 2022,
      packages_count: 100,
      versions_count: 500,
      new_packages_count: 50,
      new_versions_count: 200
    )
    @stat_2023 = RegistryGrowthStat.create!(
      registry: @registry,
      year: 2023,
      packages_count: 180,
      versions_count: 900,
      new_packages_count: 80,
      new_versions_count: 400
    )
  end

  test 'should get index' do
    get growth_path
    assert_response :success
    assert_template 'growth/index'
  end

  test 'index shows registry name' do
    get growth_path
    assert_response :success
    assert_includes response.body, @registry.name
  end

  test 'index shows charts when stats exist' do
    get growth_path
    assert_response :success
    assert_includes response.body, 'Cumulative Packages'
    assert_includes response.body, 'New Packages per Year'
  end

  test 'index shows info message when no stats exist' do
    RegistryGrowthStat.destroy_all
    get growth_path
    assert_response :success
    assert_includes response.body, 'rake growth_stats:calculate'
  end

  test 'should get show' do
    get growth_registry_path(@registry.name)
    assert_response :success
    assert_template 'growth/show'
  end

  test 'show displays registry name' do
    get growth_registry_path(@registry.name)
    assert_response :success
    assert_includes response.body, @registry.name
  end

  test 'show displays historical data table' do
    get growth_registry_path(@registry.name)
    assert_response :success
    assert_includes response.body, '2022'
    assert_includes response.body, '2023'
    assert_includes response.body, 'Total Packages'
    assert_includes response.body, 'New Packages'
  end

  test 'show displays growth rates' do
    get growth_registry_path(@registry.name)
    assert_response :success
    assert_includes response.body, '+80.0%'
  end

  test 'show handles registry not found' do
    get growth_registry_path('nonexistent')
    assert_response :not_found
  end

  test 'show displays info message when no stats exist for registry' do
    other_registry = Registry.create(name: 'npmjs.org', url: 'https://npmjs.org', ecosystem: 'npm')
    get growth_registry_path(other_registry.name)
    assert_response :success
    assert_includes response.body, 'rake growth_stats:calculate_for'
  end

  test 'show displays charts' do
    get growth_registry_path(@registry.name)
    assert_response :success
    assert_includes response.body, 'Cumulative Packages'
    assert_includes response.body, 'Cumulative Versions'
    assert_includes response.body, 'New Packages per Year'
    assert_includes response.body, 'New Versions per Year'
  end
end
