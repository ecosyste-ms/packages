require "test_helper"

class SpackTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Spack.io', url: 'https://spack.github.io', ecosystem: 'spack')
    @ecosystem = Ecosystem::Spack.new(@registry.url)
    @package = Package.new(ecosystem: 'spack', name: '3proxy')
    @version = @package.versions.build(number: '0.8.13')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://spack.github.io/packages/package.html?name=3proxy'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://spack.github.io/packages/package.html?name=3proxy'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_nil download_url
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
    assert_equal install_command, 'spack install 3proxy'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'spack install 3proxy@0.8.13'
  end

  test 'all_package_names' do
    stub_request(:get, "https://spack.github.io/packages/data/packages.json")
      .to_return({ status: 200, body: file_fixture('spack/packages.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 6371
    assert_equal all_package_names.last, 'zziplib'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://spack.github.io/packages/data/packages.json")
      .to_return({ status: 200, body: file_fixture('spack/packages.json') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 6371
    assert_equal recently_updated_package_names.last, 'zziplib'
  end

  test 'package_metadata' do
    stub_request(:get, "https://spack.github.io/packages/data/packages/3proxy.json")
      .to_return({ status: 200, body: file_fixture('spack/3proxy.json') })
    package_metadata = @ecosystem.package_metadata('3proxy')
    
    assert_equal package_metadata[:name], "3proxy"
    assert_equal package_metadata[:description], "3proxy - tiny free proxy server\n"
    assert_equal package_metadata[:homepage], "https://3proxy.org"
    assert_equal package_metadata[:licenses], []
    assert_equal package_metadata[:repository_url], "https://3proxy.org"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://spack.github.io/packages/data/packages/3proxy.json")
      .to_return({ status: 200, body: file_fixture('spack/3proxy.json') })
    package_metadata = @ecosystem.package_metadata('3proxy')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.8.13"}, {:number=>"0.8.12"}, {:number=>"0.8.11"}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://spack.github.io/packages/data/packages/3proxy.json")
      .to_return({ status: 200, body: file_fixture('spack/3proxy.json') })
    package_metadata = @ecosystem.package_metadata('3proxy')
    dependencies_metadata = @ecosystem.dependencies_metadata('3proxy', '0.8.13', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"autoconf", :requirements=>"*", :kind=>"runtime", :ecosystem=>"Spack"},
      {:package_name=>"automake", :requirements=>"*", :kind=>"runtime", :ecosystem=>"Spack"},
      {:package_name=>"libtool", :requirements=>"*", :kind=>"runtime", :ecosystem=>"Spack"},
      {:package_name=>"m4", :requirements=>"*", :kind=>"runtime", :ecosystem=>"Spack"}
    ]
  end
end
