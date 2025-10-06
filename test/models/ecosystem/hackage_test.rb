require "test_helper"

class HackageTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Hackage.haskell.org', url: 'https://hackage.haskell.org', ecosystem: 'hackage')
    @ecosystem = Ecosystem::Hackage.new(@registry)
    @package = Package.new(ecosystem: 'hackage', name: 'blockfrost-client')
    @version = @package.versions.build(number: '0.4.0.1')
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://hackage.haskell.org/package/blockfrost-client'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://hackage.haskell.org/package/blockfrost-client-0.4.0.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://hackage.haskell.org/package/blockfrost-client-0.4.0.1/blockfrost-client-0.4.0.1.tar.gz'
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
    assert_equal check_status_url, "https://hackage.haskell.org/package/blockfrost-client"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:hackage/blockfrost-client'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:hackage/blockfrost-client@0.4.0.1'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://hackage.haskell.org/packages/names")
      .to_return({ status: 200, body: file_fixture('hackage/names') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 16464
    assert_equal all_package_names.last, 'zydiskell'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://hackage.haskell.org/packages/recent.rss")
      .to_return({ status: 200, body: file_fixture('hackage/recent.rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 65
    assert_equal recently_updated_package_names.last, 'modern-uri'
  end

  test 'package_metadata' do
    stub_request(:get, "https://hackage.haskell.org/package/blockfrost-client")
      .to_return({ status: 200, body: file_fixture('hackage/blockfrost-client') })
    package_metadata = @ecosystem.package_metadata('blockfrost-client')
    
    assert_equal package_metadata[:name], "blockfrost-client"
    assert_equal package_metadata[:description], "Simple Blockfrost clients for use with transformers or mtl"
    assert_equal package_metadata[:homepage], "https://github.com/blockfrost/blockfrost-haskell"
    assert_equal package_metadata[:licenses], "Apache-2.0"
    assert_equal package_metadata[:repository_url], "https://github.com/blockfrost/blockfrost-haskell"
    assert_equal package_metadata[:keywords_array], ["apache", "cardano", "library"]
    assert_equal package_metadata[:downloads], 303
    assert_equal package_metadata[:downloads_period], 'total'
  end

  test 'versions_metadata' do
    stub_request(:get, "https://hackage.haskell.org/package/blockfrost-client")
      .to_return({ status: 200, body: file_fixture('hackage/blockfrost-client') })
    stub_request(:get, "https://hackage.haskell.org/package/blockfrost-client.rss")
      .to_return({ status: 200, body: file_fixture('hackage/blockfrost-client.rss') })
    package_metadata = @ecosystem.package_metadata('blockfrost-client')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.7.0.0", :published_at=>'2022-10-11 05:27:03 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.6.0.0", :published_at=>'2022-08-31 16:48:50 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.5.0.0", :published_at=>'2022-06-06 09:39:24 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.4.0.1", :published_at=>'2022-04-05 13:37:46 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.4.0.0", :published_at=>'2022-03-09 13:44:08 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.3.1.0", :published_at=>'2022-02-17 13:31:46 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.3.0.0", :published_at=>'2022-02-07 10:45:13 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.2.1.0", :published_at=>'2021-11-15 12:19:04 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.2.0.0", :published_at=>'2021-10-29 12:15:41 UTC', :metadata=>{:author=>"srk"}},
      {:number=>"0.1.0.0", :published_at=>'2021-09-14 12:23:58 UTC', :metadata=>{:author=>"srk"}}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://hackage.haskell.org/package/aeson-0.2.0.0")
      .to_return({ status: 200, body: file_fixture('hackage/aeson-0.2.0.0') })
    dependencies_metadata = @ecosystem.dependencies_metadata('aeson', '0.2.0.0', nil)

    assert_equal dependencies_metadata, [
      {:package_name=>"attoparsec", :requirements=>">=0.8.5.0", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"base", :requirements=>">=4 && <4.4", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"blaze-builder", :requirements=>">=0.2.1.4", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"bytestring", :requirements=>"*", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"containers", :requirements=>"*", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"deepseq", :requirements=>"<1.2", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"monads-fd", :requirements=>"*", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"old-locale", :requirements=>"*", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"syb", :requirements=>"*", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"text", :requirements=>">=0.11.0.2", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"time", :requirements=>"<1.5", :kind=>"runtime", :ecosystem=>"hackage"},
      {:package_name=>"vector", :requirements=>">=0.7", :kind=>"runtime", :ecosystem=>"hackage"}]
  end

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://hackage.haskell.org/user/foo'
  end
end
