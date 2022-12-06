require "test_helper"

class VcpkgTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'vcpkg.org', url: 'https://vcpkg.org', ecosystem: 'vcpkg')
    @ecosystem = Ecosystem::Vcpkg.new(@registry)
    @package = Package.new(ecosystem: 'vcpkg', name: 'zziplib')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_nil registry_url
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_nil registry_url
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
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
    assert_equal install_command, ".\vcpkg install zziplib"
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, ".\vcpkg install zziplib"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:vcpkg/zziplib'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:vcpkg/zziplib@1.26.8'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://vcpkg.io/output.json")
      .to_return({ status: 200, body: file_fixture('vcpkg/output.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2022
    assert_equal all_package_names.last, 'zziplib'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/microsoft/vcpkg/commits/master.atom")
      .to_return({ status: 200, body: file_fixture('vcpkg/master.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 16
    assert_equal recently_updated_package_names.last, 'folly'
  end

  test 'package_metadata' do
    stub_request(:get, "https://vcpkg.io/output.json")
      .to_return({ status: 200, body: file_fixture('vcpkg/output.json') })
    package_metadata = @ecosystem.package_metadata('zziplib')

    assert_equal package_metadata[:name], "zziplib"
    assert_equal package_metadata[:description], "library providing read access on ZIP-archives"
    assert_equal package_metadata[:homepage], "https://github.com/gdraheim/zziplib"
    assert_equal package_metadata[:licenses], "LGPL-2.0-or-later OR MPL-1.1"
    assert_equal package_metadata[:repository_url], "https://github.com/gdraheim/zziplib"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://vcpkg.io/output.json")
      .to_return({ status: 200, body: file_fixture('vcpkg/output.json') })
    package_metadata = @ecosystem.package_metadata('zziplib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.13.72"}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://vcpkg.io/output.json")
      .to_return({ status: 200, body: file_fixture('vcpkg/output.json') })
    package_metadata = @ecosystem.package_metadata('7zip')
    dependencies_metadata = @ecosystem.dependencies_metadata('7zip', '22.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"vcpkg-cmake", :requirements=>"*", :kind=>"runtime", :ecosystem=>"vcpkg"},
      {:package_name=>"vcpkg-cmake-config", :requirements=>"*", :kind=>"runtime", :ecosystem=>"vcpkg"}
    ]
  end
end
