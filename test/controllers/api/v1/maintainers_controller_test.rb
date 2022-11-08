require 'test_helper'

class ApiV1MaintainerControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @maintainer = @registry.maintainers.create(uuid: "1", login: 'rand', name: 'random', email: 'ran@d.om')
  end

  test 'list maintainers for a registry' do
    get api_v1_registry_maintainers_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'maintainers/index', file: 'maintainers/index.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a maintainer for a registry' do
    get api_v1_registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)
    assert_response :success
    assert_template 'maintainers/show', file: 'maintainers/show.json.jbuilder'
    
    actual_response = JSON.parse(@response.body)

    assert_equal actual_response["name"], @maintainer.name
    assert_equal actual_response["login"], @maintainer.login
  end
end