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
end