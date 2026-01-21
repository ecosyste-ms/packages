require 'test_helper'

class PackagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand', metadata: {foo: 'bar'})
  end

  test 'list packages for a registry' do
    get registry_packages_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'packages/index', file: 'packages/index.html.erb'
  end

  test 'get a package for a registry' do
    get registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_template 'packages/show', file: 'packages/show.html.erb'
  end

  test 'get a package with nil keywords should not error' do
    package = @registry.packages.create(ecosystem: 'cargo', name: 'test-package', keywords: nil)
    get registry_package_path(registry_id: @registry.name, id: package.name)
    assert_response :success
    assert_template 'packages/show', file: 'packages/show.html.erb'
  end

  test 'get pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get dependent_packages for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get dependent_packages_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get maintainers for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get maintainers_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get related_packages for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get related_packages_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get advisories for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get advisories_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end
end