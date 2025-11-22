require 'test_helper'

class ApiV1RegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Registry.delete_all
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @maven_registry = Registry.create(name: 'maven', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven')
  end

  test 'lists registries' do
    get api_v1_registries_path
    assert_response :success
    assert_template 'registries/index', file: 'registries/index.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 2
  end

  test 'get a registry' do
    get api_v1_registry_path(id: @registry.name)
    assert_response :success
    assert_template 'registries/show', file: 'registries/show.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response["name"], 'crates.io'
  end

  test 'filters registries by ecosystem' do
    get api_v1_registries_path(ecosystem: 'maven')
    assert_response :success
    assert_template 'registries/index', file: 'registries/index.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first["ecosystem"], 'maven'
  end

  test 'returns empty array when filtering by non-existent ecosystem' do
    get api_v1_registries_path(ecosystem: 'nonexistent')
    assert_response :success
    assert_template 'registries/index', file: 'registries/index.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 0
  end
end