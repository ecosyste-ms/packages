require "test_helper"

class SpackTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Spack.io', url: 'https://packages.spack.io', ecosystem: 'spack')
    @ecosystem = Ecosystem::Spack.new(@registry)
    @package = Package.new(ecosystem: 'spack', name: '3proxy')
    @version = @package.versions.build(number: '0.8.13', metadata: {download_url: "https://github.com/z3APA3A/3proxy/archive/0.8.13.tar.gz"})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://packages.spack.io/package.html?name=3proxy'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://packages.spack.io/package.html?name=3proxy'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://github.com/z3APA3A/3proxy/archive/0.8.13.tar.gz"
  end

  test 'download_url with array' do
    version_with_array = @package.versions.build(number: '0.8.14', metadata: {download_url: ["https://github.com/z3APA3A/3proxy/archive/0.8.14.tar.gz", "https://mirror.example.com/0.8.14.tar.gz"]})
    download_url = @ecosystem.download_url(@package, version_with_array)
    assert_equal download_url, "https://github.com/z3APA3A/3proxy/archive/0.8.14.tar.gz"
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
    assert_equal install_command, 'spack install 3proxy'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'spack install 3proxy@0.8.13'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:spack/3proxy'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:spack/3proxy@0.8.13'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://packages.spack.io/data/repology.json")
      .to_return({ status: 200, body: file_fixture('spack/repology.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 6438
    assert_equal all_package_names.last, 'zziplib'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/spack/spack/commits/develop.atom")
      .to_return({ status: 200, body: file_fixture('spack/develop.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 18
    assert_equal recently_updated_package_names.last, 'cray-mpich'
  end

  test 'package_metadata' do
    stub_request(:get, "https://packages.spack.io/data/repology.json")
      .to_return({ status: 200, body: file_fixture('spack/repology.json') })
    stub_request(:get, "https://packages.spack.io/data/packages/3proxy.json")
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
    stub_request(:get, "https://packages.spack.io/data/repology.json")
      .to_return({ status: 200, body: file_fixture('spack/repology.json') })
    stub_request(:get, "https://packages.spack.io/data/packages/3proxy.json")
      .to_return({ status: 200, body: file_fixture('spack/3proxy.json') })
    package_metadata = @ecosystem.package_metadata('3proxy')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    assert_equal versions_metadata, [
      {:number=>"0.8.13", :integrity=>"sha256-a6d3cf9dd264315fa6ec848f6fe6c9057db005ce4ca8ed1deb00f6e1c3900f88", :metadata=>{:download_url=>"https://github.com/z3APA3A/3proxy/archive/0.8.13.tar.gz"}},
      {:number=>"0.8.12", :integrity=>"sha256-c2ad3798b4f0df06cfcc7b49f658304e451d60e4834e2705ef83ddb85a03f849", :metadata=>{:download_url=>"https://github.com/z3APA3A/3proxy/archive/0.8.12.tar.gz"}},
      {:number=>"0.8.11", :integrity=>"sha256-fc4295e1a462baa61977fcc21747db7861c4e3d0dcca86cbaa3e06017e5c66c9", :metadata=>{:download_url=>"https://github.com/z3APA3A/3proxy/archive/0.8.11.tar.gz"}}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://packages.spack.io/data/repology.json")
      .to_return({ status: 200, body: file_fixture('spack/repology.json') })
    stub_request(:get, "https://packages.spack.io/data/packages/3proxy.json")
      .to_return({ status: 200, body: file_fixture('spack/3proxy.json') })
    package_metadata = @ecosystem.package_metadata('3proxy')
    dependencies_metadata = @ecosystem.dependencies_metadata('3proxy', '0.8.13', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"autoconf", :requirements=>"*", :kind=>"runtime", :ecosystem=>"spack"},
      {:package_name=>"automake", :requirements=>"*", :kind=>"runtime", :ecosystem=>"spack"},
      {:package_name=>"libtool", :requirements=>"*", :kind=>"runtime", :ecosystem=>"spack"},
      {:package_name=>"m4", :requirements=>"*", :kind=>"runtime", :ecosystem=>"spack"}
    ]
  end
end
