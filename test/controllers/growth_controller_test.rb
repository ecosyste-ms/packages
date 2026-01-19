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

  test 'export combined returns csv' do
    get growth_export_path
    assert_response :success
    assert_equal 'text/csv', response.content_type
    assert_includes response.headers['Content-Disposition'], 'growth-combined.csv'
  end

  test 'export combined includes all years' do
    get growth_export_path
    csv = CSV.parse(response.body, headers: true)
    years = csv.map { |row| row['year'].to_i }
    assert_includes years, 2022
    assert_includes years, 2023
  end

  test 'export combined has correct headers' do
    get growth_export_path
    csv = CSV.parse(response.body, headers: true)
    expected_headers = %w[year packages_count versions_count new_packages_count new_versions_count]
    assert_equal expected_headers, csv.headers
  end

  test 'export combined aggregates data across registries' do
    other_registry = Registry.create(name: 'npmjs.org', url: 'https://npmjs.org', ecosystem: 'npm')
    RegistryGrowthStat.create!(
      registry: other_registry,
      year: 2022,
      packages_count: 200,
      versions_count: 1000,
      new_packages_count: 100,
      new_versions_count: 500
    )

    get growth_export_path
    csv = CSV.parse(response.body, headers: true)
    row_2022 = csv.find { |row| row['year'] == '2022' }
    assert_equal 300, row_2022['packages_count'].to_i
    assert_equal 1500, row_2022['versions_count'].to_i
  end

  test 'export registry returns csv' do
    get growth_registry_export_path(@registry.name)
    assert_response :success
    assert_equal 'text/csv', response.content_type
    assert_includes response.headers['Content-Disposition'], "growth-#{@registry.name}.csv"
  end

  test 'export registry includes all years' do
    get growth_registry_export_path(@registry.name)
    csv = CSV.parse(response.body, headers: true)
    years = csv.map { |row| row['year'].to_i }
    assert_includes years, 2022
    assert_includes years, 2023
  end

  test 'export registry has correct headers with growth rates' do
    get growth_registry_export_path(@registry.name)
    csv = CSV.parse(response.body, headers: true)
    expected_headers = %w[year packages_count versions_count new_packages_count new_versions_count packages_growth_rate versions_growth_rate]
    assert_equal expected_headers, csv.headers
  end

  test 'export registry includes growth rates' do
    get growth_registry_export_path(@registry.name)
    csv = CSV.parse(response.body, headers: true)
    row_2023 = csv.find { |row| row['year'] == '2023' }
    assert_equal '80.0', row_2023['packages_growth_rate']
    assert_equal '80.0', row_2023['versions_growth_rate']
  end

  test 'export registry handles not found' do
    get growth_registry_export_path('nonexistent')
    assert_response :not_found
  end

  test 'index shows export csv link for combined data' do
    get growth_path
    assert_response :success
    assert_includes response.body, growth_export_path
  end

  test 'index shows export csv link for each registry' do
    get growth_path
    assert_response :success
    assert_includes response.body, growth_registry_export_path(@registry.name)
  end

  test 'show displays export csv link' do
    get growth_registry_path(@registry.name)
    assert_response :success
    assert_includes response.body, growth_registry_export_path(@registry.name)
  end
end
