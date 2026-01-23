require "test_helper"

class ConanTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'conan.io', url: 'https://conan.io/center', ecosystem: 'Conan')
    @ecosystem = Ecosystem::Conan.new(@registry)
    @package = Package.new(ecosystem: 'Conan', name: 'zlib')
    @version = @package.versions.build(number: '1.3.1', metadata: { 'url' => 'https://zlib.net/fossils/zlib-1.3.1.tar.gz' })
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://conan.io/center/recipes/zlib'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://conan.io/center/recipes/zlib?version=1.3.1'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'conan install --requires=zlib'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'conan install --requires=zlib/1.3.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://zlib.net/fossils/zlib-1.3.1.tar.gz'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://conan.io/center/recipes/zlib'
  end

  test 'all_package_names' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: file_fixture('conan/search_all.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 5
    assert_equal all_package_names.first, '7bitconf'
    assert_equal all_package_names.last, 'zlib'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/conan-io/conan-center-index/commits/master.atom")
      .to_return({ status: 200, body: file_fixture('conan/commits.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_includes recently_updated_package_names, 'zlib'
  end

  test 'package_metadata' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: file_fixture('conan/search_all.json') })
    stub_request(:get, "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes/zlib/config.yml")
      .to_return({ status: 200, body: file_fixture('conan/zlib_config.yml') })
    stub_request(:get, "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes/zlib/all/conanfile.py")
      .to_return({ status: 200, body: file_fixture('conan/zlib_conanfile.py') })
    package_metadata = @ecosystem.package_metadata('zlib')

    assert_equal package_metadata[:name], 'zlib'
    assert_equal package_metadata[:description], 'A Massively Spiffy Yet Delicately Unobtrusive Compression Library'
    assert_equal package_metadata[:homepage], 'https://zlib.net'
    assert_equal package_metadata[:licenses], 'Zlib'
    assert_equal package_metadata[:versions], ['1.3.1']
    assert_includes package_metadata[:keywords_array], 'compression'
  end

  test 'versions_metadata' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: file_fixture('conan/search_all.json') })
    stub_request(:get, "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes/zlib/config.yml")
      .to_return({ status: 200, body: file_fixture('conan/zlib_config.yml') })
    stub_request(:get, "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes/zlib/all/conanfile.py")
      .to_return({ status: 200, body: file_fixture('conan/zlib_conanfile.py') })
    stub_request(:get, "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes/zlib/all/conandata.yml")
      .to_return({ status: 200, body: file_fixture('conan/zlib_conandata.yml') })
    package_metadata = @ecosystem.package_metadata('zlib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.length, 1
    assert_equal versions_metadata.first[:number], '1.3.1'
    assert_equal versions_metadata.first[:metadata][:url], 'https://zlib.net/fossils/zlib-1.3.1.tar.gz'
  end

  test 'dependencies_metadata from api' do
    stub_request(:get, "https://conan.io/api/package/7bitconf/use_it")
      .to_return({ status: 200, body: file_fixture('conan/7bitconf_use_it.json') })
    dependencies_metadata = @ecosystem.dependencies_metadata('7bitconf', '1.2.0', nil)

    assert_equal dependencies_metadata.length, 1
    assert_equal dependencies_metadata.first[:package_name], 'taocpp-json'
    assert_equal dependencies_metadata.first[:requirements], '1.0.0-beta.14'
    assert_equal dependencies_metadata.first[:kind], 'runtime'
  end

  test 'dependencies_metadata from conanfile fallback' do
    stub_request(:get, "https://conan.io/api/package/zziplib/use_it")
      .to_return({ status: 404 })
    stub_request(:get, "https://raw.githubusercontent.com/conan-io/conan-center-index/master/recipes/zziplib/all/conanfile.py")
      .to_return({ status: 200, body: file_fixture('conan/zziplib_conanfile.py') })
    dependencies_metadata = @ecosystem.dependencies_metadata('zziplib', '0.13.78', nil)

    assert_equal dependencies_metadata.length, 2
    runtime_dep = dependencies_metadata.find { |d| d[:kind] == 'runtime' }
    dev_dep = dependencies_metadata.find { |d| d[:kind] == 'development' }
    assert_equal runtime_dep[:package_name], 'zlib'
    assert_equal runtime_dep[:requirements], '[>=1.2.11 <2]'
    assert_equal dev_dep[:package_name], 'cmake'
    assert_equal dev_dep[:requirements], '[>=3.16 <4]'
  end

  test 'check_status returns nil for active package' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: file_fixture('conan/search_all.json') })
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status returns deprecated for deprecated package' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: '{"0":{"name":"old-pkg","info":{"deprecated":"new-pkg"}}}' })
    package = Package.new(ecosystem: 'Conan', name: 'old-pkg')
    status = @ecosystem.check_status(package)
    assert_equal status, 'deprecated'
  end

  test 'check_status returns removed for missing package' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: '{}' })
    package = Package.new(ecosystem: 'Conan', name: 'nonexistent')
    status = @ecosystem.check_status(package)
    assert_equal status, 'removed'
  end

  test 'deprecation_info' do
    stub_request(:get, "https://conan.io/api/search/all?topics=&licenses=")
      .to_return({ status: 200, body: '{"0":{"name":"old-pkg","info":{"deprecated":"new-pkg"}}}' })
    deprecation_info = @ecosystem.deprecation_info('old-pkg')

    assert deprecation_info[:is_deprecated]
    assert_equal deprecation_info[:message], 'Deprecated in favor of new-pkg'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:conan/zlib'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:conan/zlib@1.3.1'
    assert Purl.parse(purl)
  end
end
