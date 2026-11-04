require "test_helper"

class PackagistTest < ActiveSupport::TestCase
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    {
      'psr/log' => 'log.json.1',
      'maztech/instagram-php-graph-sdk' => 'instagram-php-graph-sdk.json.1',
      'intervention/image' => 'intervention-image.json'
    }.each do |name, fixture|
      versions = JSON.parse(file_fixture("packagist/#{fixture}").read).fetch('package').fetch('versions').values
      versions.reject! { |v| v['version'].match?(/^dev-|\.x-dev$/i) }
      stub_request(:get, "https://repo.packagist.org/p2/#{name}.json")
        .to_return(status: 200, body: {packages: {name => versions}}.to_json, headers: {'Last-Modified' => Time.utc(2026, 11, 1).httpdate})
    end
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
    stub_request(:get, %r{https://packagist.org/metadata/changes.json\?since=\d+})
      .to_return(body: {timestamp: Time.current.to_i * 10_000, actions: [
        {type: 'update', package: 'psr/log', time: Time.current.to_i},
        {type: 'update', package: 'psr/log~dev', time: Time.current.to_i}
      ]}.to_json)
    assert_equal ['psr/log'], @ecosystem.recently_updated_package_names
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
    assert_nil first_version[:integrity]
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

  test 'dependencies_metadata leaves out every Composer platform package' do
    platform = %w[php PHP-64bit php-ipv6 php-zts php-debug hhvm ext-json ext-pdo_mysql lib-icu lib-curl-openssl composer composer-plugin-api composer-runtime-api]
    packages = %w[phpunit/phpunit php-http/client composer/composer hhvm/hhvm-autoload ext-json/ext-json]
    links = (platform + packages).index_with('*')
    release = {'version' => '1.0.0', 'require' => links, 'require-dev' => [], 'provide' => {'psr/log-implementation' => '1.0'}}

    dependencies = @ecosystem.dependencies_metadata('vendor/package', '1.0.0', {versions: {'1.0.0' => release}})
    metadata = @ecosystem.versions_metadata({versions: {'1.0.0' => release}}).first[:metadata]

    assert_equal packages, dependencies.pluck(:package_name)
    assert_equal ['runtime'], dependencies.pluck(:kind).uniq
    assert_equal platform, metadata[:platform_requirements].keys
    assert_nil metadata[:platform_requirements_dev]
    assert_equal({'psr/log-implementation' => '1.0'}, metadata[:provide])
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
      "php" => "^8.1",
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

  test 'sync worker imports current p2 releases while retaining cached package enrichment' do
    registry = packagist_sync_registry
    modified = 'Wed, 11 Sep 2024 13:21:14 GMT'
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .to_return(status: 200, body: file_fixture('packagist/log.p2.json'), headers: {'Last-Modified' => modified})
    package = SyncPackageWorker.new.perform(registry.id, 'psr/log', true)

    assert_equal '3.0.2', package.reload.latest_release_number
    assert_equal 12, package.versions.count
    assert_equal '>=8.0.0', package.versions.find_by!(number: '3.0.2').metadata['php_version']
    assert_equal 'MIT', package.licenses
    assert_equal 566842099, package.downloads
    assert_equal %w[Seldaek fig michaelcullum], package.maintainers.pluck(:login).sort
    oldest = package.versions.find_by!(number: '1.0.0')
    assert_nil oldest.metadata['extra']
    assert_nil oldest.metadata['php_version']
    assert_equal({'psr-0' => {'Psr\\Log\\' => ''}}, oldest.metadata['autoload'])

    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .with(headers: {'If-Modified-Since' => modified})
      .to_return(status: 304)
    assert_instance_of Package, SyncPackageWorker.new.perform(registry.id, 'psr/log', true)
    assert_equal 12, package.versions.count
    assert_requested(:get, 'https://packagist.org/packages/psr/log.json', times: 1)
    assert_requested(:get, 'https://repo.packagist.org/p2/psr/log.json', headers: {'If-Modified-Since' => modified}, times: 1)
  end

  test 'sync worker does not fall back to stale versions after a p2 failure' do
    registry = packagist_sync_registry
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .to_return(status: 200, body: file_fixture('packagist/log.p2.json'), headers: {'Last-Modified' => Time.utc(2026, 11, 1).httpdate})
    package = SyncPackageWorker.new.perform(registry.id, 'psr/log', true)
    synced_at = package.reload.last_synced_at

    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 503)
    travel 1.hour do
      error = assert_raises(RuntimeError) { SyncPackageWorker.new.perform(registry.id, 'psr/log', true) }
      assert_includes error.message, 'HTTP 503'
    end
    assert_equal synced_at, package.reload.last_synced_at
    assert_equal 12, package.versions.count
  end

  test 'sync worker rejects invalid p2 snapshots without caching them' do
    registry = packagist_sync_registry
    invalid = [
      ['not json', JSON::ParserError],
      [{packages: {}}, KeyError],
      [{packages: {'psr/log' => {}}}, RuntimeError],
      [{packages: {'psr/log' => [{'version' => ''}]}}, RuntimeError],
      [{minified: 'unknown', packages: {'psr/log' => []}}, RuntimeError]
    ]
    invalid.each do |body, error_class|
      stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
        .to_return(status: 200, body: body.is_a?(String) ? body : body.to_json)
      assert_raises(error_class) { SyncPackageWorker.new.perform(registry.id, 'psr/log', true) }
      assert_nil Rails.cache.read(['packagist', 'tagged_versions', 'psr/log'])
      assert_empty registry.packages
    end
  end

  test 'by-id sync propagates p2 failures without checking status or advancing the cooldown' do
    registry = packagist_sync_registry
    package = registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', last_synced_at: 2.days.ago)
    synced_at = package.reload.last_synced_at
    next_sync_at = package.next_sync_at
    version = package.versions.create!(number: '3.0.0')
    request = stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')

    request.to_return(status: 503)
    error = assert_raises(RuntimeError) { SyncPackageByIdWorker.new.perform(registry.id, package.id) }
    assert_includes error.message, 'HTTP 503'
    assert_equal synced_at, package.reload.last_synced_at

    request.to_timeout
    assert_raises(Faraday::TimeoutError) { SyncPackageByIdWorker.new.perform(registry.id, package.id) }
    assert_equal synced_at, package.reload.last_synced_at

    request.to_return(status: 200, body: 'not json')
    assert_raises(JSON::ParserError) { SyncPackageByIdWorker.new.perform(registry.id, package.id) }
    assert_equal synced_at, package.reload.last_synced_at
    assert_equal next_sync_at, package.next_sync_at
    assert_equal 'active', package[:status]
    assert_equal [version.id], package.versions.pluck(:id)
    assert_not_requested(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')

    request.to_return(status: 200, body: file_fixture('packagist/log.p2.json'), headers: {'Last-Modified' => Time.utc(2026, 11, 1).httpdate})
    SyncPackageByIdWorker.new.perform(registry.id, package.id)
    assert_operator package.reload.last_synced_at, :>, synced_at
    assert_equal '3.0.2', package.latest_release_number
    assert_equal 12, package.versions.count
  end

  test 'by-id sync still checks removal when package enrichment returns not found' do
    registry = packagist_sync_registry
    package = registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', last_synced_at: 2.days.ago)
    stub_request(:get, 'https://packagist.org/packages/psr/log.json')
      .to_return(status: 404, body: {status: 'error', message: 'Package not found'}.to_json)
    stub_request(:head, 'https://packagist.org/packages/psr/log').to_return(status: 404)

    SyncPackageByIdWorker.new.perform(registry.id, package.id)
    assert_equal 'removed', package.reload[:status]
    assert_not_requested(:get, 'https://repo.packagist.org/p2/psr/log.json')
  end

  test 'sync worker preserves development-only packages with no tagged releases' do
    registry = packagist_sync_registry
    data = JSON.parse(file_fixture('packagist/log.json.1').read)
    data['package']['versions'].select! { |number, _| number == 'dev-master' }
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(status: 200, body: data.to_json)
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .to_return(status: 200, body: {minified: 'composer/2.0', packages: {'psr/log' => []}}.to_json, headers: {'Last-Modified' => Time.utc(2026, 11, 1).httpdate})

    package = SyncPackageWorker.new.perform(registry.id, 'psr/log', true)
    assert_equal 'psr/log', package.name
    assert_equal 0, package.versions.count
    assert_equal 'MIT', package.licenses
    assert_equal 3, package.maintainers.count
  end

  test 'sync worker refreshes enrichment after its cache expires' do
    registry = packagist_sync_registry
    SyncPackageWorker.new.perform(registry.id, 'psr/log', true)
    data = JSON.parse(file_fixture('packagist/log.json.1').read)
    data['package']['downloads']['total'] = 600000000
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(status: 200, body: data.to_json)

    travel 13.hours do
      package = SyncPackageWorker.new.perform(registry.id, 'psr/log', true)
      assert_equal 600000000, package.reload.downloads
    end
    assert_requested(:get, 'https://packagist.org/packages/psr/log.json', times: 2)
  end

  def packagist_sync_registry
    registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'packagist', default: true)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    stub_request(:get, 'https://packagist.org/packages/psr/log.json')
      .to_return(status: 200, body: file_fixture('packagist/log.json.1'))
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(status: 200, body: {packages: {'psr/log' => [{'version' => 'dev-master'}]}}.to_json)
    registry
  end
end
