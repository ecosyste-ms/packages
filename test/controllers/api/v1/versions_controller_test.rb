require 'test_helper'

class ApiV1VersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand')
    @version = @package.versions.create(number: '1.0.0', metadata: {foo: 'bar'})
  end

  test 'list versions for a package' do
    get api_v1_registry_package_versions_path(registry_id: @registry.name, package_id: @package.name)
    assert_response :success
    assert_template 'versions/index', file: 'packages/versions.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get version of a package' do
    get api_v1_registry_package_version_path(registry_id: @registry.name, package_id: @package.name, id: '1.0.0')
    assert_response :success
    assert_template 'versions/show', file: 'versions/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response['number'], "1.0.0"
    assert_equal actual_response['metadata'], {"foo"=>"bar"}
  end

  test 'get recent versions' do
    get recent_versions_api_v1_registry_path(id: @registry.name)
    assert_response :success
    assert_template 'versions/recent', file: 'versions/recent.json.jbuilder'

    actual_response = JSON.parse(@response.body)

    first_version = actual_response.first

    assert_equal first_version['ecosystem'], "cargo"
    assert_equal first_version['name'], "rand"
    assert_equal first_version['number'], "1.0.0"
    assert_equal first_version['metadata'], {"foo"=>"bar"}
  end
end