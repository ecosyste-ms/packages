require 'test_helper'

class SortSanitizationTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand', downloads: 100)
  end

  # -- PackagesController --

  test 'packages index with valid sort param' do
    get registry_packages_path(registry_id: @registry.name, sort: 'downloads', order: 'desc')
    assert_response :success
  end

  test 'packages index with stargazers_count sort' do
    get registry_packages_path(registry_id: @registry.name, sort: 'stargazers_count', order: 'desc')
    assert_response :success
  end

  test 'packages index with invalid sort falls back to default' do
    get registry_packages_path(registry_id: @registry.name, sort: '1;DROP TABLE packages--')
    assert_response :success
  end

  test 'packages index with sql injection in sort param' do
    get registry_packages_path(registry_id: @registry.name, sort: "name; DELETE FROM packages")
    assert_response :success
    assert_equal 1, @registry.packages.count
  end

  test 'packages dependent_packages with invalid sort falls back to default' do
    get dependent_packages_registry_package_path(registry_id: @registry.name, id: @package.name, sort: 'malicious_column')
    assert_response :success
  end

  test 'packages related_packages with invalid sort falls back to default' do
    get related_packages_registry_package_path(registry_id: @registry.name, id: @package.name, sort: 'malicious_column')
    assert_response :success
  end

  # -- RegistriesController --

  test 'registries keyword with valid sort' do
    @package.update(keywords: ['testing'])
    get keyword_registry_path(id: @registry.name, keyword: 'testing', sort: 'downloads')
    assert_response :success
  end

  test 'registries keyword with invalid sort falls back to default' do
    @package.update(keywords: ['testing'])
    get keyword_registry_path(id: @registry.name, keyword: 'testing', sort: 'DROP TABLE packages')
    assert_response :success
    assert_equal 1, @registry.packages.count
  end

  # -- NamespacesController --

  test 'namespaces show with invalid sort falls back to default' do
    @package.update(namespace: 'test-ns')
    get registry_namespace_path(registry_id: @registry.name, id: 'test-ns', sort: '1;DROP TABLE packages--')
    assert_response :success
  end

  # -- MaintainersController --

  test 'maintainers index with valid sort' do
    maintainer = Maintainer.create(login: 'testuser', uuid: SecureRandom.uuid, registry: @registry, packages_count: 1)
    get registry_maintainers_path(registry_id: @registry.name, sort: 'packages_count')
    assert_response :success
  end

  test 'maintainers index with invalid sort falls back to default' do
    maintainer = Maintainer.create(login: 'testuser', uuid: SecureRandom.uuid, registry: @registry, packages_count: 1)
    get registry_maintainers_path(registry_id: @registry.name, sort: 'malicious_column')
    assert_response :success
  end

  test 'maintainers show with invalid sort falls back to default' do
    maintainer = Maintainer.create(login: 'testuser', uuid: SecureRandom.uuid, registry: @registry)
    @package.maintainers << maintainer
    get registry_maintainer_path(registry_id: @registry.name, id: maintainer.login, sort: '1;DROP TABLE packages--')
    assert_response :success
  end

  # -- CriticalController --

  test 'critical index with valid sort' do
    @package.update(critical: true)
    get critical_path(sort: 'downloads', order: 'asc')
    assert_response :success
  end

  test 'critical index with invalid sort falls back to default' do
    @package.update(critical: true)
    get critical_path(sort: '1;DROP TABLE packages--')
    assert_response :success
    assert_equal 1, @registry.packages.count
  end

  # -- API PackagesController --

  test 'api packages index with valid sort' do
    get api_v1_registry_packages_path(registry_id: @registry.name, sort: 'downloads', order: 'desc')
    assert_response :success
  end

  test 'api packages index with invalid sort falls back to default' do
    get api_v1_registry_packages_path(registry_id: @registry.name, sort: '1;DROP TABLE packages--')
    assert_response :success
    assert_equal 1, @registry.packages.count
  end

  test 'api packages index with stargazers_count sort' do
    get api_v1_registry_packages_path(registry_id: @registry.name, sort: 'stargazers_count')
    assert_response :success
  end

  test 'api packages names with invalid sort falls back to default' do
    get package_names_api_v1_registry_path(id: @registry.name, sort: 'malicious')
    assert_response :success
  end

  test 'api packages lookup with invalid sort falls back to default' do
    get lookup_api_v1_packages_path(purl: 'pkg:cargo/rand', sort: 'malicious')
    assert_response :success
  end

  test 'api packages dependent_packages with invalid sort falls back to default' do
    get dependent_packages_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name, sort: 'malicious')
    assert_response :success
  end

  test 'api packages related_packages with invalid sort falls back to default' do
    get related_packages_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name, sort: 'malicious')
    assert_response :success
  end

  # -- API CriticalController --

  test 'api critical index with invalid sort falls back to default' do
    @package.update(critical: true)
    get api_v1_critical_index_path(sort: '1;DROP TABLE packages--')
    assert_response :success
    assert_equal 1, @registry.packages.count
  end

  # -- API VersionsController --

  test 'api versions index with valid sort' do
    version = @package.versions.create(number: '1.0.0', published_at: 1.day.ago)
    get api_v1_registry_package_versions_path(registry_id: @registry.name, package_id: @package.name, sort: 'published_at')
    assert_response :success
  end

  test 'api versions index with invalid sort falls back to default' do
    version = @package.versions.create(number: '1.0.0', published_at: 1.day.ago)
    get api_v1_registry_package_versions_path(registry_id: @registry.name, package_id: @package.name, sort: 'malicious')
    assert_response :success
  end

  test 'api versions recent with invalid sort falls back to default' do
    version = @package.versions.create(number: '1.0.0', published_at: 1.day.ago)
    get versions_api_v1_registry_path(id: @registry.name, sort: '1;DROP TABLE packages--')
    assert_response :success
  end

  # -- API DependenciesController --

  test 'api dependencies index with valid sort' do
    get api_v1_dependencies_path(sort: 'id', order: 'asc')
    assert_response :success
  end

  test 'api dependencies index with invalid sort falls back to default' do
    get api_v1_dependencies_path(sort: '1;DROP TABLE packages--')
    assert_response :success
    assert_equal 1, Package.where(name: 'rand').count
  end

  # -- API MaintainersController --

  test 'api maintainers index with valid sort' do
    maintainer = Maintainer.create(login: 'testuser', uuid: SecureRandom.uuid, registry: @registry, packages_count: 1)
    get api_v1_registry_maintainers_path(registry_id: @registry.name, sort: 'login', order: 'asc')
    assert_response :success
  end

  test 'api maintainers index with invalid sort falls back to default' do
    maintainer = Maintainer.create(login: 'testuser', uuid: SecureRandom.uuid, registry: @registry, packages_count: 1)
    get api_v1_registry_maintainers_path(registry_id: @registry.name, sort: 'malicious_column')
    assert_response :success
  end

  test 'api maintainers index with multi-column sort filters invalid columns' do
    maintainer = Maintainer.create(login: 'testuser', uuid: SecureRandom.uuid, registry: @registry, packages_count: 1)
    get api_v1_registry_maintainers_path(registry_id: @registry.name, sort: 'login,malicious', order: 'asc,desc')
    assert_response :success
  end
end
