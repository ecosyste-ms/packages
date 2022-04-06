require 'test_helper'

class ApiV1RegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Registry.delete_all
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
  end

  test 'lists registries' do
    get api_v1_registries_path
    assert_response :success
    assert_template 'registries/index', file: 'registries/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a registry' do
    get api_v1_registry_path(id: @registry.name)
    assert_response :success
    assert_template 'registries/show', file: 'registries/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["name"], 'crates.io'
  end
end