require 'test_helper'

class ApiV1MaintainerControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @maintainer = @registry.maintainers.create(uuid: "1", login: 'rand', name: 'random', email: 'ran@d.om')
    @package = @registry.packages.create(name: 'rand', ecosystem: @registry.ecosystem)
    @version = @package.versions.create(number: '0.1.0', published_at: Time.now)
    @package.maintainers << @maintainer
  end

  test 'list maintainers for a registry' do
    get api_v1_registry_maintainers_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'maintainers/index', file: 'maintainers/index.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get a maintainer for a registry' do
    get api_v1_registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)
    assert_response :success
    assert_template 'maintainers/show', file: 'maintainers/show.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response["name"], @maintainer.name
    assert_equal actual_response["login"], @maintainer.login
  end

  test 'get packages for a maintainer' do
    get packages_api_v1_registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)
    assert_response :success
    assert_template 'maintainers/packages', file: 'maintainers/packages.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response[0]["name"], @package.name
  end

  test 'hidden maintainers are omitted from the registry list' do
    @registry.maintainers.create!(uuid: 'hidden-uuid', login: 'hidden-user', packages_count: Maintainer::TOMBSTONE_PACKAGES_COUNT)

    get api_v1_registry_maintainers_path(registry_id: @registry.name)

    assert_response :success
    assert_equal ['rand'], Oj.load(response.body).pluck('login')
  end

  test 'hidden maintainer endpoints return not found' do
    @maintainer.update!(packages_count: Maintainer::TOMBSTONE_PACKAGES_COUNT)

    get api_v1_registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)
    assert_response :not_found

    get packages_api_v1_registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)
    assert_response :not_found
  end
end
