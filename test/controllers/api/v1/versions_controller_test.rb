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
end