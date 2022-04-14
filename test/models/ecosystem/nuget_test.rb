require "test_helper"

class NugetTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'NuGet.org', url: 'https://www.nuget.org', ecosystem: 'nuget')
    @ecosystem = Ecosystem::Nuget.new(@registry.url)
    @package = Package.new(ecosystem: 'nuget', name: 'urllib3')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://www.nuget.org/packages/urllib3/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'https://www.nuget.org/packages/urllib3/1.26.8'
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

  test 'package_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-semver1/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    package_metadata = @ecosystem.package_metadata('OgcApi.Net.SqlServer')
    
    assert_equal package_metadata[:name], "OgcApi.Net.SqlServer"
    assert_equal package_metadata[:description], "SQL Server provider for the OGC API Features Standard implementation"
    assert_nil package_metadata[:homepage]
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], ""
    assert_equal package_metadata[:keywords_array], [""]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-semver1/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    package_metadata = @ecosystem.package_metadata('OgcApi.Net.SqlServer')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.3.0", :published_at=>"2022-03-25T05:11:36.793+00:00"},
      {:number=>"0.3.1", :published_at=>"2022-03-25T10:25:47.79+00:00"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-semver1/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    package_metadata = @ecosystem.package_metadata('OgcApi.Net.SqlServer')
    dependencies_metadata = @ecosystem.dependencies_metadata('OgcApi.Net.SqlServer', '0.3.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"OgcApi.Net", :requirements=>">= 0.3.0", :kind=>"runtime", :optional=>false, :ecosystem=>"nuget"},
      {:package_name=>"Microsoft.Data.SqlClient", :requirements=>">= 3.0.1", :kind=>"runtime", :optional=>false, :ecosystem=>"nuget"},
      {:package_name=>"NetTopologySuite.IO.SqlServerBytes", :requirements=>">= 2.0.0", :kind=>"runtime", :optional=>false, :ecosystem=>"nuget"}
    ]
  end
end
