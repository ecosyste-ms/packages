require 'test_helper'

class ApiV1DependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand')
    @version = @package.versions.create(number: '1.0.0', metadata: {foo: 'bar'})
    @dependency = @version.dependencies.create(ecosystem: 'cargo', package_name: 'rand', requirements: '1.0.0', kind: 'normal', optional: false)
  end

  test 'list dependencies for a package' do
    get api_v1_dependencies_url(package_name: 'rand')
    assert_response :success
    assert_equal 1, JSON.parse(@response.body).size
  end

  test 'list dependencies when version has no package' do
    @package.delete

    get api_v1_dependencies_url(package_name: 'rand')
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal 1, body.size
    assert_nil body.first['package']
    assert_nil body.first['version']
    assert_equal 'rand', body.first['package_name']
  end

  test 'filter dependencies by version_id' do
    other_version = @package.versions.create(number: '2.0.0')
    other_version.dependencies.create(ecosystem: 'cargo', package_name: 'rand_core', requirements: '0.3.0', kind: 'normal', optional: false)

    get api_v1_dependencies_url(version_id: @version.id)
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal 1, body.size
    assert_equal @dependency.id, body.first['id']
    assert_equal @version.id, body.first['version']['id']
  end

  test 'filter dependencies by version_id combined with kind' do
    other_version = @package.versions.create(number: '2.0.0')
    other_version.dependencies.create(ecosystem: 'cargo', package_name: 'rand_core', requirements: '0.3.0', kind: 'normal', optional: false)
    @version.dependencies.create(ecosystem: 'cargo', package_name: 'rand_chacha', requirements: '0.1.0', kind: 'build', optional: false)

    get api_v1_dependencies_url(version_id: @version.id, kind: 'normal')
    assert_response :success

    body = JSON.parse(@response.body)
    assert_equal 1, body.size
    assert_equal @dependency.id, body.first['id']
  end

  test 'filter dependencies by version_id returns empty for version without dependencies' do
    empty_version = @package.versions.create(number: '3.0.0')

    get api_v1_dependencies_url(version_id: empty_version.id)
    assert_response :success
    assert_equal [], JSON.parse(@response.body)
  end

  test 'list dependencies without version_id returns all versions dependencies' do
    other_version = @package.versions.create(number: '2.0.0')
    other_version.dependencies.create(ecosystem: 'cargo', package_name: 'rand_core', requirements: '0.3.0', kind: 'normal', optional: false)

    get api_v1_dependencies_url
    assert_response :success
    assert_equal 2, JSON.parse(@response.body).size
  end
end
