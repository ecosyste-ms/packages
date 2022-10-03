require "test_helper"

class PackagistTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @ecosystem = Ecosystem::Packagist.new(@registry)
    @package = Package.new(ecosystem: 'Packagist', name: 'psr/log')
    @version = @package.versions.build(number: '3.0.0', :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/fe5ea303b0887d5caefd3d431c3e61ad47037001"})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://packagist.org/packages/psr/log#'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://packagist.org/packages/psr/log#3.0.0'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://api.github.com/repos/php-fig/log/zipball/fe5ea303b0887d5caefd3d431c3e61ad47037001"
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
    assert_equal install_command, 'composer require psr/log'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'composer require psr/log:3.0.0'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://packagist.org/packages/psr/log#"
  end

  test 'all_package_names' do
    stub_request(:get, "https://packagist.org/packages/list.json")
      .to_return({ status: 200, body: file_fixture('packagist/list.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 331163
    assert_equal all_package_names.last, 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz/no-trailing-comma'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://packagist.org/feeds/releases.rss")
      .to_return({ status: 200, body: file_fixture('packagist/releases.rss') })
    stub_request(:get, "https://packagist.org/feeds/packages.rss")
    .to_return({ status: 200, body: file_fixture('packagist/packages.rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 75
    assert_equal recently_updated_package_names.last, 'pringuin/pimcore-lucene-search'
  end

  test 'package_metadata' do
    stub_request(:get, "https://packagist.org/packages/psr/log.json")
      .to_return({ status: 200, body: file_fixture('packagist/log.json.1') })
    package_metadata = @ecosystem.package_metadata('psr/log')

    assert_equal package_metadata[:name], "psr/log"
    assert_equal package_metadata[:description], "Common interface for logging libraries"
    assert_equal package_metadata[:homepage], "https://github.com/php-fig/log"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/php-fig/log"
    assert_equal package_metadata[:keywords_array], ["log", "psr", "psr-3"]
    assert_equal package_metadata[:downloads], 566842099
    assert_equal package_metadata[:downloads_period], 'total'
  end

  test 'versions_metadata' do
    stub_request(:get, "https://packagist.org/packages/psr/log.json")
      .to_return({ status: 200, body: file_fixture('packagist/log.json.1') })
    package_metadata = @ecosystem.package_metadata('psr/log')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"3.0.0", :published_at=>"2021-07-14T16:46:02+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/fe5ea303b0887d5caefd3d431c3e61ad47037001"}},
      {:number=>"2.0.0", :published_at=>"2021-07-14T16:41:46+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/ef29f6d262798707a9edd554e2b82517ef3a9376"}},
      {:number=>"1.1.4", :published_at=>"2021-05-03T11:20:27+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/d49695b909c3b7628b6289db5479a1c204601f11"}},
      {:number=>"1.1.3", :published_at=>"2020-03-23T09:12:05+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/0f73288fd15629204f9d42b7055f72dacbe811fc"}},
      {:number=>"1.1.2", :published_at=>"2019-11-01T11:05:21+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/446d54b4cb6bf489fc9d75f55843658e6f25d801"}},
      {:number=>"1.1.1", :published_at=>"2019-10-25T08:06:51+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/bf73deb2b3b896a9d9c75f3f0d88185d2faa27e2"}},
      {:number=>"1.1.0", :published_at=>"2018-11-20T15:27:04+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/6c001f1daafa3a3ac1d8ff69ee4db8e799a654dd"}},
      {:number=>"1.0.2", :published_at=>"2016-10-10T12:19:37+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/4ebe3a8bf773a19edfe0a84b6585ba3d401b724d"}},
      {:number=>"1.0.1", :published_at=>"2016-09-19T16:02:08+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/5277094ed527a1c4477177d102fe4c53551953e0"}},
      {:number=>"1.0.0", :published_at=>"2012-12-21T11:40:51+00:00", :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/fe0936ee26643249e916849d48e3a51d5f5e278b"}}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://packagist.org/packages/maztech/instagram-php-graph-sdk.json")
      .to_return({ status: 200, body: file_fixture('packagist/instagram-php-graph-sdk.json.1') })
    package_metadata = @ecosystem.package_metadata('maztech/instagram-php-graph-sdk')
    dependencies_metadata = @ecosystem.dependencies_metadata('maztech/instagram-php-graph-sdk', 'v1.0.0', package_metadata)
    
    assert_equal dependencies_metadata, [
      {:package_name=>"phpunit/phpunit", :requirements=>"~4.0", :kind=>"Development", :optional=>false, :ecosystem=>"packagist"},
      {:package_name=>"mockery/mockery", :requirements=>"~0.8", :kind=>"Development", :optional=>false, :ecosystem=>"packagist"},
      {:package_name=>"guzzlehttp/guzzle", :requirements=>"~5.0", :kind=>"Development", :optional=>false, :ecosystem=>"packagist"}
    ]
  end
end
