require "test_helper"

class NuGetTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'NuGet.org', url: 'https://www.nuget.org', ecosystem: 'nuget')
    @ecosystem = Ecosystem::NuGet.new(@registry.url)
    @package = Package.new(ecosystem: 'nuget', name: 'urllib3')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://www.nuget.org/packages/urllib3/'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://www.nuget.org/packages/urllib3/1.26.8'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://www.nuget.org/api/v2/package/urllib3/1.26.8'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'Install-Package urllib3'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'Install-Package urllib3 -Version 1.26.8'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://www.nuget.org/packages/urllib3/"
  end

  test 'all_package_names' do
    stub_request(:get, "https://api.nuget.org/v3/catalog0/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/index.json') })
    stub_request(:get, "https://api.nuget.org/v3/catalog0/page15386.json")
      .to_return({ status: 200, body: file_fixture('nuget/page15386.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 223
    assert_equal all_package_names.last, 'RedCounterSoftware.DataAccess.RavenDb'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://api.nuget.org/v3/catalog0/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/index.json') })
    stub_request(:get, "https://api.nuget.org/v3/catalog0/page15386.json")
      .to_return({ status: 200, body: file_fixture('nuget/page15386.json') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 203
    assert_equal recently_updated_package_names.last, 'TS.Services.Messaging'
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
