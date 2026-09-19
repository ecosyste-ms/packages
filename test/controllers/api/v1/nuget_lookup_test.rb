require 'test_helper'

class ApiV1NugetLookupTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'nuget.org', url: 'https://api.nuget.org/v3/index.json', ecosystem: 'nuget')
    @package = @registry.packages.create!(ecosystem: 'nuget', name: 'system.runtime.serialization.formatters')
    @published_name = 'System.Runtime.Serialization.Formatters'
  end

  test 'registry name lookup normalizes NuGet casing and keeps the registry restriction' do
    alternate = Registry.create!(name: 'alternate-nuget', url: 'https://nuget.example/index.json', ecosystem: 'nuget')
    alternate.packages.create!(ecosystem: 'nuget', name: @package.name)

    get lookup_api_v1_registry_path(id: @registry.name), params: { ecosystem: 'nuget', name: @published_name }

    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')
  end

  test 'registry name lookup normalizes NuGet casing without an ecosystem parameter' do
    get lookup_api_v1_registry_path(id: @registry.name), params: { name: @published_name }

    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')
  end

  test 'global name lookup normalizes NuGet casing and keeps the ecosystem restriction' do
    other = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    other.packages.create!(ecosystem: 'cargo', name: @package.name)

    get lookup_api_v1_packages_path, params: { ecosystem: 'nuget', name: @published_name }

    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')
  end

  test 'global PURL lookup resolves NuGet names with mixed uppercase and lowercase casing' do
    [@published_name, @published_name.upcase, @package.name].each do |name|
      get lookup_api_v1_packages_path, params: { purl: "pkg:nuget/#{name}" }

      assert_response :success
      assert_equal [@package.id], Oj.load(response.body).pluck('id')
    end
  end

  test 'NuGet PURL normalization preserves repository_url qualifiers' do
    alternate = Registry.create!(name: 'alternate-nuget', url: 'https://nuget.example/index.json', ecosystem: 'nuget')
    package = alternate.packages.create!(ecosystem: 'nuget', name: @package.name)

    get lookup_api_v1_packages_path, params: {
      purl: "pkg:nuget/#{@published_name}?repository_url=https://nuget.example/index.json"
    }

    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')
  end

  test 'bulk PURL lookup normalizes NuGet names without changing other ecosystems' do
    registry = Registry.create!(name: 'cocoapods.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods')
    package = registry.packages.create!(ecosystem: 'cocoapods', name: 'MixedCase')
    registry.packages.create!(ecosystem: 'cocoapods', name: 'mixedcase')

    post bulk_lookup_api_v1_packages_path, params: {
      purls: ["pkg:nuget/#{@published_name}", 'pkg:cocoapods/MixedCase']
    }

    assert_response :success
    assert_equal [@package.id, package.id].sort, Oj.load(response.body).pluck('id').sort
  end

  test 'name and PURL lookups retain exact matching for case-sensitive ecosystems' do
    registry = Registry.create!(name: 'cocoapods.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods')
    package = registry.packages.create!(ecosystem: 'cocoapods', name: 'MixedCase')
    registry.packages.create!(ecosystem: 'cocoapods', name: 'mixedcase')

    get lookup_api_v1_registry_path(id: registry.name), params: { name: 'MixedCase' }
    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')

    get lookup_api_v1_packages_path, params: { ecosystem: 'cocoapods', name: 'MixedCase' }
    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')

    get lookup_api_v1_packages_path, params: { purl: 'pkg:cocoapods/MixedCase' }
    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')
  end

  test 'NuGet normalization does not broaden lookups for missing packages' do
    get lookup_api_v1_packages_path, params: { purl: 'pkg:nuget/Does.Not.Exist' }
    assert_response :success
    assert_empty Oj.load(response.body)

    post bulk_lookup_api_v1_packages_path, params: { purls: ['pkg:nuget/Does.Not.Exist'] }
    assert_response :success
    assert_empty Oj.load(response.body)
  end
end
