require "test_helper"

class PypiTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    @ecosystem = Ecosystem::Pypi.new(@registry.url)
    @package = Package.new(ecosystem: 'pypi', name: 'urllib3')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://pypi.org/package/urllib3/'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://pypi.org/package/urllib3/1.26.8'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, 'https://urllib3.readthedocs.io/'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, 'https://urllib3.readthedocs.io/en/1.26.8'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'pip install urllib3 --index-url https://pypi.org/simple'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'pip install urllib3==1.26.8 --index-url https://pypi.org/simple'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://pypi.org/package/urllib3/"
  end

  test 'all_package_names' do
    stub_request(:get, "https://pypi.org/simple/")
      .to_return({ status: 200, body: file_fixture('pypi/index.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 364372
    assert_equal all_package_names.last, 'zzzZZZzzz'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://pypi.org/rss/updates.xml")
      .to_return({ status: 200, body: file_fixture('pypi/updates.xml') })
    stub_request(:get, "https://pypi.org/rss/packages.xml")
    .to_return({ status: 200, body: file_fixture('pypi/packages.xml') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 114
    assert_equal recently_updated_package_names.last, 'Lgy'
  end

  test 'fetch_package_metadata' do
    skip("To be implemented")
  end

  test 'map_package_metadata' do
    skip("To be implemented")
  end

  test 'versions_metadata' do
    skip("To be implemented")
  end

  test 'dependencies_metadata' do
    skip("To be implemented")
  end
end
