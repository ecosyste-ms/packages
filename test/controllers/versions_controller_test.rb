require 'test_helper'

class VersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand')
    @version = @package.versions.create(number: '1.0.0', metadata: {foo: 'bar'})
  end

  test 'get version of a package' do
    stub_request(:get, "https://archives.ecosyste.ms/api/v1/archives/list?url=https://crates.io/api/v1/crates/rand/1.0.0/download").
      to_return(status: 200, body: file_fixture('list?url=https:%2F%2Fcrates.io%2Fapi%2Fv1%2Fcrates%2Frand%2F1.0.0%2Fdownload'))

    get registry_package_version_path(registry_id: @registry.name, package_id: @package.name, id: '1.0.0')
    assert_response :success
    assert_template 'versions/show', file: 'versions/show.html.erb'
  end

  test 'get recent versions' do
    get versions_registry_path(id: @registry.name)
    assert_response :success
    assert_template 'versions/recent', file: 'versions/recent.html.erb'
  end
end