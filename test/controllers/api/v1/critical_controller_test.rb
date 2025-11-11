require 'test_helper'

class Api::V1::CriticalControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'npmjs.org', url: 'https://npmjs.com', ecosystem: 'npm')
    @maintainer = Maintainer.create(name: 'Test User', uuid: SecureRandom.uuid, registry: @registry, login: 'testuser')

    @critical_package = @registry.packages.create(
      ecosystem: 'npm',
      name: 'critical-pkg',
      critical: true,
      downloads: 1000,
      maintainers_count: 1,
      issue_metadata: {
        'maintainers' => [{'login' => 'testuser'}]
      }
    )
    @critical_package.maintainers << @maintainer

    @non_critical_package = @registry.packages.create(
      ecosystem: 'npm',
      name: 'non-critical-pkg',
      critical: false
    )
  end

  test 'should get index' do
    get api_v1_critical_index_path, as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.is_a?(Array)
    assert_equal 1, json_response.count
    assert_equal 'critical-pkg', json_response.first['name']
  end

  test 'should filter index by registry' do
    other_registry = Registry.create(name: 'pypi', url: 'https://pypi.org', ecosystem: 'pypi')
    other_package = other_registry.packages.create(
      ecosystem: 'pypi',
      name: 'other-pkg',
      critical: true
    )

    get api_v1_critical_index_path(registry: @registry.name), as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response.count
    assert_equal 'critical-pkg', json_response.first['name']
  end

  test 'should get sole_maintainers' do
    get sole_maintainers_api_v1_critical_index_path, as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.is_a?(Array)
    assert_equal 1, json_response.count
    assert_equal 'critical-pkg', json_response.first['name']
  end

  test 'should get maintainers' do
    get maintainers_api_v1_critical_index_path, as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.is_a?(Array)
    assert_equal 1, json_response.count

    maintainer = json_response.first
    assert_equal 'testuser', maintainer['login']
    assert_equal 1, maintainer['packages_count']
    assert_equal 'npmjs.org', maintainer['registry_name']
    assert maintainer['packages'].is_a?(Array)
    assert_equal 'critical-pkg', maintainer['packages'].first['name']
  end

  test 'should filter maintainers by registry' do
    other_registry = Registry.create(name: 'pypi', url: 'https://pypi.org', ecosystem: 'pypi')
    other_maintainer = Maintainer.create(name: 'Other User', uuid: SecureRandom.uuid, registry: other_registry, login: 'otheruser')
    other_package = other_registry.packages.create(
      ecosystem: 'pypi',
      name: 'other-pkg',
      critical: true
    )
    other_package.maintainers << other_maintainer

    get maintainers_api_v1_critical_index_path(registry: @registry.name), as: :json
    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response.count
    assert_equal 'testuser', json_response.first['login']
  end
end
