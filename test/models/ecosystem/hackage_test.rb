require "test_helper"

class HackageTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Hackage.haskell.org', url: 'http://hackage.haskell.org', ecosystem: 'hackage')
    @ecosystem = Ecosystem::Hackage.new(@registry.url)
    @package = Package.new(ecosystem: 'hackage', name: 'blockfrost-client')
    @version = @package.versions.build(number: '0.4.0.1')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'http://hackage.haskell.org/package/blockfrost-client'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'http://hackage.haskell.org/package/blockfrost-client-0.4.0.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'http://hackage.haskell.org/package/blockfrost-client-0.4.0.1/blockfrost-client-0.4.0.1.tar.gz'
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
    assert_equal install_command, 'cabal install blockfrost-client'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'cabal install blockfrost-client-0.4.0.1'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "http://hackage.haskell.org/package/blockfrost-client"
  end

  test 'all_package_names' do
    stub_request(:get, "http://hackage.haskell.org/packages/names")
      .to_return({ status: 200, body: file_fixture('hackage/names') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 16464
    assert_equal all_package_names.last, 'zydiskell'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "http://hackage.haskell.org/packages/recent.rss")
      .to_return({ status: 200, body: file_fixture('hackage/recent.rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 65
    assert_equal recently_updated_package_names.last, 'modern-uri'
  end

  test 'package_metadata' do
    stub_request(:get, "http://hackage.haskell.org/package/blockfrost-client")
      .to_return({ status: 200, body: file_fixture('hackage/blockfrost-client') })
    package_metadata = @ecosystem.package_metadata('blockfrost-client')
    
    assert_equal package_metadata[:name], "blockfrost-client"
    assert_equal package_metadata[:description], "Simple Blockfrost clients for use with transformers or mtl"
    assert_equal package_metadata[:homepage], "https://github.com/blockfrost/blockfrost-haskell"
    assert_equal package_metadata[:licenses], "Apache-2.0"
    assert_equal package_metadata[:repository_url], "https://github.com/blockfrost/blockfrost-haskell"
    assert_equal package_metadata[:keywords_array], ["apache", "cardano", "library"]
  end

  test 'versions_metadata' do
    stub_request(:get, "http://hackage.haskell.org/package/blockfrost-client")
      .to_return({ status: 200, body: file_fixture('hackage/blockfrost-client') })
    package_metadata = @ecosystem.package_metadata('blockfrost-client')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.1.0.0"}, {:number=>"0.2.0.0"}, {:number=>"0.2.1.0"}, {:number=>"0.3.0.0"}, {:number=>"0.3.1.0"}, {:number=>"0.4.0.0"}, {:number=>"0.4.0.1"}]
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('blockfrost-client', '0.1.2.32', nil)

    assert_equal dependencies_metadata, []
  end
end
