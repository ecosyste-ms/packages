require "test_helper"

class NugetTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'NuGet.org', url: 'https://www.nuget.org', ecosystem: 'nuget')
    @ecosystem = Ecosystem::Nuget.new(@registry)
    @package = Package.new(ecosystem: 'nuget', name: 'ogcapi.net.sqlserver')
    @version = @package.versions.build(number: '0.3.1')
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://www.nuget.org/packages/ogcapi.net.sqlserver/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://www.nuget.org/packages/ogcapi.net.sqlserver/0.3.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.1/ogcapi.net.sqlserver.0.3.1.nupkg'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'Install-Package ogcapi.net.sqlserver'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'Install-Package ogcapi.net.sqlserver -Version 0.3.1'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/index.json"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:nuget/ogcapi.net.sqlserver'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:nuget/ogcapi.net.sqlserver@0.3.1'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://api.nuget.org/v3/catalog0/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/index.json') })
    stub_request(:get, "https://api.nuget.org/v3/catalog0/page15386.json")
      .to_return({ status: 200, body: file_fixture('nuget/page15386.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 223
    assert_equal all_package_names.last, 'redcountersoftware.dataaccess.ravendb'
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
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:ogcapi.net.sqlserver")
      .to_return({ status: 200, body: file_fixture('nuget/query?q=packageid:OgcApi.Net.SqlServer') })
    package_metadata = @ecosystem.package_metadata('ogcapi.net.sqlserver')
    
    assert_equal package_metadata[:name], "ogcapi.net.sqlserver"
    assert_equal package_metadata[:description], "SQL Server provider for the OGC API Features Standard implementation"
    assert_equal package_metadata[:homepage], "https://github.com/sam-is/OgcApi.Net"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], ""
    assert_equal package_metadata[:keywords_array], []
    assert_equal package_metadata[:downloads], 1331
    assert_equal package_metadata[:downloads_period], "total"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-semver1/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:ogcapi.net.sqlserver")
      .to_return({ status: 200, body: file_fixture('nuget/query?q=packageid:OgcApi.Net.SqlServer') })
    package_metadata = @ecosystem.package_metadata('ogcapi.net.sqlserver')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.3.0", :published_at=>"2022-03-25T05:11:36.793+00:00", metadata: {downloads: 92}},
      {:number=>"0.3.1", :published_at=>"2022-03-25T10:25:47.79+00:00", metadata: {downloads: 83}}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-semver1/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:ogcapi.net.sqlserver")
      .to_return({ status: 200, body: file_fixture('nuget/query?q=packageid:OgcApi.Net.SqlServer') })
    package_metadata = @ecosystem.package_metadata('ogcapi.net.sqlserver')
    dependencies_metadata = @ecosystem.dependencies_metadata('ogcapi.net.sqlserver', '0.3.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"ogcapi.net", :requirements=>">= 0.3.0", :kind=>"runtime", :optional=>false, :ecosystem=>"nuget"},
      {:package_name=>"microsoft.data.sqlclient", :requirements=>">= 3.0.1", :kind=>"runtime", :optional=>false, :ecosystem=>"nuget"},
      {:package_name=>"nettopologysuite.io.sqlserverbytes", :requirements=>">= 2.0.0", :kind=>"runtime", :optional=>false, :ecosystem=>"nuget"}
    ]
  end

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://www.nuget.org/profiles/foo'
  end
end
