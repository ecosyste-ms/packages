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
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:ogcapi.net.sqlserver")
      .to_return({ status: 200, body: file_fixture('nuget/query_packageid:OgcApi.Net.SqlServer') })
    # Mock .nuspec requests for all versions
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.0/ogcapi.net.sqlserver.nuspec")
      .to_return({ status: 404, body: "" }) # Simulate missing .nuspec
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.1/ogcapi.net.sqlserver.nuspec")
      .to_return({ status: 404, body: "" }) # Simulate missing .nuspec
    package_metadata = @ecosystem.package_metadata('ogcapi.net.sqlserver')
    
    assert_equal package_metadata[:name], "ogcapi.net.sqlserver"
    assert_equal package_metadata[:description], "SQL Server provider for the OGC API Features Standard implementation"
    assert_equal package_metadata[:homepage], "https://github.com/sam-is/OgcApi.Net"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/sam-is/OgcApi.Net"
    assert_equal package_metadata[:keywords_array], []
    assert_equal package_metadata[:downloads], 1331
    assert_equal package_metadata[:downloads_period], "total"
    
    # Check that metadata is present (even if .nuspec requests fail)
    metadata = package_metadata[:metadata]
    assert_not_nil metadata
  end

  test 'versions_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:ogcapi.net.sqlserver")
      .to_return({ status: 200, body: file_fixture('nuget/query_packageid:OgcApi.Net.SqlServer') })
    # Mock .nuspec requests for all versions
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.0/ogcapi.net.sqlserver.nuspec")
      .to_return({ status: 404, body: "" })
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.1/ogcapi.net.sqlserver.nuspec")
      .to_return({ status: 404, body: "" })
    package_metadata = @ecosystem.package_metadata('ogcapi.net.sqlserver')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    # Test basic structure
    assert_equal 2, versions_metadata.length
    
    # Check version numbers and published dates
    assert_equal "0.3.0", versions_metadata[0][:number]
    assert_equal "2022-03-25T05:11:36.793+00:00", versions_metadata[0][:published_at]
    assert_equal "0.3.1", versions_metadata[1][:number]
    assert_equal "2022-03-25T10:25:47.79+00:00", versions_metadata[1][:published_at]
    
    # Check that metadata now includes enhanced information
    metadata_0 = versions_metadata[0][:metadata]
    assert_not_nil metadata_0
    assert_equal 92, metadata_0[:downloads]
    
    # Should have API metadata fields
    assert metadata_0.has_key?(:api_description)
    assert metadata_0.has_key?(:api_authors)
    assert metadata_0.has_key?(:api_license_expression)
    
    # Should have catalog entry ID
    assert metadata_0.has_key?(:catalog_entry_id)
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/ogcapi.net.sqlserver/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/ogcapi.net.sqlserver') })
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:ogcapi.net.sqlserver")
      .to_return({ status: 200, body: file_fixture('nuget/query_packageid:OgcApi.Net.SqlServer') })
    # Mock .nuspec requests for all versions
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.0/ogcapi.net.sqlserver.nuspec")
      .to_return({ status: 404, body: "" })
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/ogcapi.net.sqlserver/0.3.1/ogcapi.net.sqlserver.nuspec")
      .to_return({ status: 404, body: "" })
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

  test 'newtonsoft.json package_metadata extracts comprehensive nuspec metadata' do
    # Mock the registration API response
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_registration.json') })
    
    # Mock the search API response 
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:newtonsoft.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_search.json') })
    
    # Mock the .nuspec file API response (this will be called for each version)
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.nuspec")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_nuspec.xml') })
    
    package_metadata = @ecosystem.package_metadata('newtonsoft.json')
    
    # Basic package metadata should still work
    assert_equal package_metadata[:name], "newtonsoft.json"
    assert_equal package_metadata[:description], "Json.NET is a popular high-performance JSON framework for .NET"
    assert_equal package_metadata[:homepage], "https://www.newtonsoft.com/json"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal "https://github.com/JamesNK/Newtonsoft.Json", package_metadata[:repository_url]
    
    # Enhanced package metadata from .nuspec (NuGet-specific only)
    metadata = package_metadata[:metadata]
    assert_not_nil metadata
    
    # NuGet-specific package information
    assert_equal "Copyright © James Newton-King 2008", metadata[:copyright]
    
    # Repository information (detailed)
    repository_info = metadata[:repository]
    assert_not_nil repository_info
    assert_equal "git", repository_info[:type]
    assert_equal "https://github.com/JamesNK/Newtonsoft.Json", repository_info[:url]
    assert_equal "0a2e291c0d9c0c7675d445703e51750363a549ef", repository_info[:commit]
    
    # License information (detailed)
    license_info = metadata[:license_info]
    assert_not_nil license_info
    assert_equal "expression", license_info[:type]
    assert_equal "MIT", license_info[:text]
    
    # URLs and resources
    assert_equal "https://www.newtonsoft.com/content/images/nugeticon.png", metadata[:icon_url]
    assert_equal "packageIcon.png", metadata[:icon]
    assert_equal "README.md", metadata[:readme]
    
    # Technical information
    assert_equal "2.12", metadata[:min_client_version]
    assert_equal false, metadata[:require_license_acceptance]
  end

  test 'newtonsoft.json versions_metadata includes comprehensive nuspec data' do
    # Mock the registration API response
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_registration.json') })
    
    # Mock the search API response 
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:newtonsoft.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_search.json') })
    
    # Mock the .nuspec file API response
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.nuspec")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_nuspec.xml') })
    
    package_metadata = @ecosystem.package_metadata('newtonsoft.json')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    assert_equal 1, versions_metadata.length
    
    version_metadata = versions_metadata.first
    assert_equal "13.0.3", version_metadata[:number]
    
    # Version-specific metadata
    vm = version_metadata[:metadata]
    assert_not_nil vm
    
    # Both API and .nuspec metadata should be present
    assert_not_nil vm[:api_description]
    assert_not_nil vm[:nuspec_description]
    
    # Repository information should be detailed
    repository_info = vm[:repository]
    assert_not_nil repository_info
    assert_equal "git", repository_info[:type]
    assert_equal "https://github.com/JamesNK/Newtonsoft.Json", repository_info[:url]
    
    # License information should be comprehensive
    license_info = vm[:license_info]
    assert_not_nil license_info
    assert_equal "expression", license_info[:type]
    assert_equal "MIT", license_info[:text]
    
    # Technical details
    assert_equal "2.12", vm[:min_client_version]
    assert_equal "Newtonsoft.Json", vm[:nuspec_id]
    assert_equal "Json.NET", vm[:nuspec_title]
    assert_equal "James Newton-King", vm[:nuspec_authors]
    
    # Metadata source comparison analysis
    comparison = vm[:metadata_source_comparison]
    assert_not_nil comparison
    assert comparison.has_key?(:description_differs)
    assert comparison.has_key?(:title_differs)
    assert comparison.has_key?(:authors_differs)
  end

  test 'update_versions with comprehensive nuspec metadata integration' do
    # Create a test registry and package
    registry = Registry.create(name: 'NuGet.org', url: 'https://www.nuget.org', ecosystem: 'nuget')
    package = registry.packages.create!(
      name: 'newtonsoft.json',
      ecosystem: 'nuget',
      description: 'Json.NET is a popular high-performance JSON framework for .NET',
      homepage: 'https://www.newtonsoft.com/json'
    )

    # Mock all required API responses
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_registration.json') })
    
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:newtonsoft.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_search.json') })
    
    # Mock .nuspec file for the version
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.nuspec")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_nuspec.xml') })

    # Before update_versions
    assert_equal 0, package.versions.count
    
    # Run update_versions which should use comprehensive metadata
    package.update_versions
    
    # After update_versions
    package.reload
    assert_equal 1, package.versions.count
    
    version = package.versions.first
    assert_equal "13.0.3", version.number
    assert_not_nil version.published_at
    
    # Check comprehensive version metadata was stored
    metadata = version.metadata
    assert_not_nil metadata
    
    # Should have both API and .nuspec fields
    assert_not_nil metadata["api_description"]
    assert_not_nil metadata["nuspec_description"]
    assert_not_nil metadata["api_authors"]
    assert_not_nil metadata["nuspec_authors"]
    
    # Should have detailed repository information
    repository_info = metadata["repository"]
    assert_not_nil repository_info
    assert_equal "git", repository_info["type"]
    assert_equal "https://github.com/JamesNK/Newtonsoft.Json", repository_info["url"]
    assert_equal "0a2e291c0d9c0c7675d445703e51750363a549ef", repository_info["commit"]
    
    # Should have structured license information
    license_info = metadata["license_info"]
    assert_not_nil license_info
    assert_equal "expression", license_info["type"]
    assert_equal "MIT", license_info["text"]
    
    # Should have technical metadata
    assert_equal "2.12", metadata["min_client_version"]
    assert_equal "Newtonsoft.Json", metadata["nuspec_id"]
    assert_equal "Json.NET", metadata["nuspec_title"]
    assert_equal "James Newton-King", metadata["nuspec_authors"]
    
    # Should have dependency information
    dependency_groups = metadata["dependency_groups"]
    assert_not_nil dependency_groups
    assert dependency_groups.is_a?(Array)
    assert dependency_groups.length > 0
    
    # Should have metadata comparison
    comparison = metadata["metadata_source_comparison"]
    assert_not_nil comparison
    assert comparison.has_key?("description_differs")
    assert comparison.has_key?("title_differs")
  end

  test 'package sync with comprehensive nuspec metadata integration' do
    # Create a test registry and package with minimal data
    registry = Registry.create(name: 'NuGet.org', url: 'https://www.nuget.org', ecosystem: 'nuget')
    package = registry.packages.create!(
      name: 'newtonsoft.json',
      ecosystem: 'nuget'
    )

    # Mock all required API responses
    stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_registration.json') })
    
    stub_request(:get, "https://azuresearch-usnc.nuget.org/query?q=packageid:newtonsoft.json")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_search.json') })
    
    # Mock .nuspec file for comprehensive metadata
    stub_request(:get, "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.nuspec")
      .to_return({ status: 200, body: file_fixture('nuget/newtonsoft.json_nuspec.xml') })

    # Before sync - should have minimal data
    assert_nil package.repository_url
    assert_equal({}, package.metadata || {})
    
    # Run manual sync with comprehensive metadata
    ecosystem = Ecosystem::Nuget.new(registry)
    metadata = ecosystem.package_metadata('newtonsoft.json')
    package.update!(metadata.except(:releases, :download_stats, :versions))
    package.reload
    
    # After sync - should have comprehensive metadata
    assert_equal "https://github.com/JamesNK/Newtonsoft.Json", package.repository_url
    assert_equal "Json.NET is a popular high-performance JSON framework for .NET", package.description
    assert_equal "https://www.newtonsoft.com/json", package.homepage
    assert_equal "MIT", package.licenses
    
    # Check comprehensive package metadata was stored (NuGet-specific only)
    pkg_metadata = package.metadata
    assert_not_nil pkg_metadata
    
    # Should have NuGet-specific package info from .nuspec
    assert_equal "Copyright © James Newton-King 2008", pkg_metadata["copyright"]
    
    # Should have structured repository information
    repository_info = pkg_metadata["repository"]
    assert_not_nil repository_info
    assert_equal "git", repository_info["type"]
    assert_equal "https://github.com/JamesNK/Newtonsoft.Json", repository_info["url"]
    assert_equal "0a2e291c0d9c0c7675d445703e51750363a549ef", repository_info["commit"]
    
    # Should have license details
    license_info = pkg_metadata["license_info"]
    assert_not_nil license_info
    assert_equal "expression", license_info["type"]
    assert_equal "MIT", license_info["text"]
    
    # Should have resource URLs
    assert_equal "https://www.newtonsoft.com/content/images/nugeticon.png", pkg_metadata["icon_url"]
    assert_equal "packageIcon.png", pkg_metadata["icon"]
    assert_equal "README.md", pkg_metadata["readme"]
    
    # Should have technical information
    assert_equal "2.12", pkg_metadata["min_client_version"]
    assert_equal false, pkg_metadata["require_license_acceptance"]
    
    # Should have dependency summary
    dependency_summary = pkg_metadata["dependency_summary"]
    assert_not_nil dependency_summary
    assert dependency_summary.has_key?("total_dependency_groups")
    assert dependency_summary.has_key?("target_frameworks")
    assert dependency_summary.has_key?("total_dependencies")
  end
end
