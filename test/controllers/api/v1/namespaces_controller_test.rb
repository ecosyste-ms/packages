require 'test_helper'

class ApiV1NamespacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @namespace = 'foo'
    @package = @registry.packages.create(name: 'rand', ecosystem: @registry.ecosystem, namespace: @namespace)
    @version = @package.versions.create(number: '0.1.0', published_at: Time.now)
  end

  test 'list namespaces for a registry' do
    get api_v1_registry_namespaces_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'namespaces/index', file: 'namespaces/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a namespace for a registry' do
    get api_v1_registry_namespace_path(registry_id: @registry.name, id: @namespace)
    assert_response :success
    assert_template 'namespaces/show', file: 'namespaces/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["name"], @namespace
  end

  test 'get packages for a namespace' do
    get packages_api_v1_registry_namespace_path(registry_id: @registry.name, id: @namespace)
    assert_response :success
    assert_template 'namespaces/packages', file: 'namespaces/packages.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response[0]["name"], @package.name
  end
end