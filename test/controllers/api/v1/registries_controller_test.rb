require 'test_helper'

class ApiV1RegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Registry.delete_all
    @registry = Registry.create(name: 'Crates.io', url: 'https://crates.io', ecosystem: 'Cargo')
  end

  test 'creates new saved searches' do
    get api_v1_registries_path
    assert_response :success
    assert_template 'registries/index', file: 'registries/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end
end