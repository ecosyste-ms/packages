require "test_helper"

class JuliaTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'juliahub.com', url: 'http://juliahub.com', ecosystem: 'julia')
    @ecosystem = Ecosystem::Julia.new(@registry.url)
    @package = Package.new(ecosystem: 'julia', name: 'Inequality', metadata: {slug: 'xDAp7'})
    @version = @package.versions.build(number: '0.0.4')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://juliahub.com/ui/Packages/Inequality/xDAp7/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://juliahub.com/ui/Packages/Inequality/xDAp7/0.0.4'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://docs.juliahub.com/Inequality/xDAp7/'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, 'https://docs.juliahub.com/Inequality/xDAp7/0.0.4'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'Pkg.add("Inequality")'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'Pkg.add(Pkg.PackageSpec(;name="Inequality", version="0.0.4"))'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://juliahub.com/ui/Packages/Inequality/xDAp7"
  end

  test 'all_package_names' do
    stub_request(:get, "https://juliahub.com/app/packages/info")
      .to_return({ status: 200, body: file_fixture('julia/info') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 7442
    assert_equal all_package_names.last, 'ZygoteStructArrays'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/JuliaRegistries/General/commits/master/Registry.toml.atom")
      .to_return({ status: 200, body: file_fixture('julia/Registry.toml.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 20
    assert_equal recently_updated_package_names.last, 'Inequality'
  end

  test 'package_metadata' do
    stub_request(:get, "https://juliahub.com/app/packages/info")
      .to_return({ status: 200, body: file_fixture('julia/info') })
    package_metadata = @ecosystem.package_metadata('Inequality')
    
    assert_equal package_metadata[:name], "Inequality"
    assert_equal package_metadata[:description], "Julia package for computing inequality indicators"
    assert_nil package_metadata[:homepage]
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/JosepER/Inequality.jl.git"
    assert_equal package_metadata[:keywords_array], []
  end

  test 'versions_metadata' do
    stub_request(:get, "https://juliahub.com/app/packages/info")
      .to_return({ status: 200, body: file_fixture('julia/info') })
    package_metadata = @ecosystem.package_metadata('Inequality')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.0.4"}]
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('Inequality', '0.0.4', {})

    assert_equal dependencies_metadata, []
  end
end
