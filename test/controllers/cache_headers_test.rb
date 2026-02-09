require 'test_helper'

class CacheHeadersTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create!(ecosystem: 'cargo', name: 'rand', metadata: { foo: 'bar' })
  end

  test "home index sets public cache headers with s-maxage" do
    get root_path
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=21600"
    assert_cache_control "stale-while-revalidate=21600"
    assert_cache_control "stale-if-error=86400"
  end

  test "packages index sets public cache headers" do
    get registry_packages_path(registry_id: @registry.name)
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=21600"
  end

  test "packages show sets public cache headers" do
    get registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=21600"
  end

  test "api packages index sets shorter s-maxage" do
    get api_v1_registry_packages_path(registry_id: @registry.name)
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=3600"
  end

  test "api packages show sets shorter s-maxage" do
    get api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_cache_control "public"
    assert_cache_control "s-maxage=3600"
  end

  def assert_cache_control(directive)
    cc = response.headers['Cache-Control'] || ''
    assert cc.include?(directive), "Expected Cache-Control to include '#{directive}', got '#{cc}'"
  end
end
