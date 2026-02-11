require "test_helper"

class PackagistTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @ecosystem = Ecosystem::Packagist.new(@registry)
    @package = Package.new(ecosystem: 'Packagist', name: 'psr/log')
    @version = @package.versions.build(number: '3.0.0', :metadata=>{:download_url=>"https://api.github.com/repos/php-fig/log/zipball/fe5ea303b0887d5caefd3d431c3e61ad47037001"})
    @maintainer = @registry.maintainers.build(login: 'foo')
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

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:composer/psr/log'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:composer/psr/log@3.0.0'
    assert Purl.parse(purl)
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
    assert_equal package_metadata[:namespace], 'psr'
  end

  test 'versions_metadata' do
    stub_request(:get, "https://packagist.org/packages/psr/log.json")
      .to_return({ status: 200, body: file_fixture('packagist/log.json.1') })
    package_metadata = @ecosystem.package_metadata('psr/log')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    first_version = versions_metadata.first
    assert_equal first_version[:number], "3.0.0"
    assert_equal first_version[:published_at], "2021-07-14T16:46:02+00:00"
    assert_equal first_version[:metadata][:php_version], ">=8.0.0"
    assert_equal first_version[:metadata][:autoload], {"psr-4"=>{"Psr\\Log\\"=>"src"}}
    assert_equal first_version[:metadata][:extra], {"branch-alias"=>{"dev-master"=>"3.x-dev"}}
    
    older_version = versions_metadata.find { |v| v[:number] == "1.1.4" }
    assert_equal older_version[:metadata][:php_version], ">=5.3.0"
    
    assert_equal versions_metadata.length, 10
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

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://packagist.org/users/foo'
  end

  test 'versions_metadata includes PHP version and platform requirements' do
    stub_request(:get, "https://packagist.org/packages/intervention/image.json")
      .to_return({ status: 200, body: file_fixture('packagist/intervention-image.json') })
    package_metadata = @ecosystem.package_metadata('intervention/image')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:number], "3.8.0"
    assert_equal first_version[:metadata][:php_version], "^8.1"
    assert_equal first_version[:metadata][:platform_requirements], {
      "ext-mbstring" => "*"
    }
    assert_equal first_version[:metadata][:suggest], {
      "ext-gd" => "to use GD library based image processing",
      "ext-imagick" => "to use Imagick based image processing"
    }
    assert_equal first_version[:metadata][:autoload], {"psr-4" => {"Intervention\\Image\\" => "src"}}
    assert first_version[:metadata][:extra].key?("laravel")
  end

  test 'check_status reuses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://packagist.org/packages/psr/log.json")
      .to_return({ status: 200, body: file_fixture('packagist/log.json.1') })
    stub_request(:get, "https://repo.packagist.org/p2/psr/log~dev.json")
      .to_return({ status: 200, body: '{"packages":{"psr/log":[{"version":"dev-master"}]}}' })

    # Fetch metadata first to populate the cache
    @ecosystem.package_metadata('psr/log')

    # check_status should reuse cached data, skipping the HEAD request
    status = @ecosystem.check_status(@package)
    assert_nil status

    # The packages API should only have been called once (for the initial fetch)
    assert_requested(:get, "https://packagist.org/packages/psr/log.json", times: 1)
    # The HEAD request to registry URL should NOT have been made
    assert_not_requested(:head, "https://packagist.org/packages/psr/log")
  end
end
