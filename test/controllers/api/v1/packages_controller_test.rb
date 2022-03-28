require 'test_helper'

class ApiV1PackagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'Crates.io', url: 'https://crates.io', ecosystem: 'Cargo')
    @package = @registry.packages.create(ecosystem: 'Cargo', name: 'rand')
  end

  test 'creates new saved searches' do
    get api_v1_registry_packages_path(registry_id: @registry.id)
    assert_response :success
    assert_template 'packages/index', file: 'packages/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end
end