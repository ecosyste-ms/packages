require 'test_helper'

class MaintainersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @maintainer = @registry.maintainers.create(uuid: "1", login: 'rand', name: 'random', email: 'ran@d.om')
    @package = @registry.packages.create(name: 'rand', ecosystem: @registry.ecosystem)
    @version = @package.versions.create(number: '0.1.0', published_at: Time.now)
    @package.maintainers << @maintainer
  end

  test 'list maintainers for a registry' do
    get registry_maintainers_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'maintainers/index', file: 'maintainers/index.json.jbuilder'
  end

  test 'get a maintainer for a registry' do
    get registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)
    assert_response :success
    assert_template 'maintainers/show', file: 'maintainers/show.json.jbuilder'
  end

  test 'hidden maintainers are omitted from the registry list' do
    hidden = @registry.maintainers.create!(uuid: 'hidden-uuid', login: 'hidden-user', packages_count: Maintainer::TOMBSTONE_PACKAGES_COUNT)

    get registry_maintainers_path(registry_id: @registry.name)

    assert_response :success
    assert_not_includes response.body, hidden.login
  end

  test 'hidden maintainer pages return not found' do
    @maintainer.update!(packages_count: Maintainer::TOMBSTONE_PACKAGES_COUNT)

    get registry_maintainer_path(registry_id: @registry.name, id: @maintainer.login)

    assert_response :not_found
  end
end
