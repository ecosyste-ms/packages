require "test_helper"

class NpmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @ecosystem = Ecosystem::Npm.new(@registry)
    @package = Package.new(ecosystem: 'npm', name: 'base62')
    @version = @package.versions.build(number: '2.0.1')
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://www.npmjs.com/package/base62'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://www.npmjs.com/package/base62/v/2.0.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://registry.npmjs.org/base62/-/base62-2.0.1.tgz"
  end

  test 'download_url for namespaced packages' do
    @package.name = '@digital-boss/n8n-nodes-mollie'
    download_url = @ecosystem.download_url(@package, '0.2.0')
    assert_equal download_url, "https://registry.npmjs.org/@digital-boss/n8n-nodes-mollie/-/n8n-nodes-mollie-0.2.0.tgz"
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
    assert_equal install_command, 'npm install base62'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'npm install base62@2.0.1'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://registry.npmjs.org/base62"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:npm/base62'
    assert Purl.parse(purl)
  end

  test 'purl with namespace' do
    @package = Package.new(ecosystem: 'npm', name: '@fudge-ai/browser', namespace: 'fudge-ai')
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:npm/%40fudge-ai/browser'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:npm/base62@2.0.1'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json")
      .to_return({ status: 200, body: file_fixture('npm/names.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 290
    assert_equal all_package_names.last, '03-creatfront'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://npm.ecosyste.ms/recent")
      .to_return({ status: 200, body: file_fixture('npm/recent') })
    stub_request(:get, "https://registry.npmjs.org/-/rss?descending=true&limit=50")
      .to_return({ status: 200, body: file_fixture('npm/new-rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 250
    assert_equal recently_updated_package_names.last, 'test-raydium-sdk-v2'
  end

  test 'package_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })
    package_metadata = @ecosystem.package_metadata('base62')

    assert_equal package_metadata[:name], "base62"
    assert_equal package_metadata[:description], "JavaScript Base62 encode/decoder"
    assert_equal package_metadata[:homepage], "https://github.com/base62/base62.js"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/base62/base62.js"
    assert_equal package_metadata[:keywords_array], ["base-62", "encoder", "decoder"]
    assert_nil package_metadata[:downloads]
    assert_equal package_metadata[:downloads_period], "last-month"
    assert_not_requested :get, "https://api.npmjs.org/downloads/point/last-month/base62"
    assert_nil package_metadata[:namespace]
    assert_equal package_metadata[:metadata], {"funding"=>nil, "dist-tags"=>{"latest"=>"2.0.1"}, "contentPolicy"=>nil}
  end

  test 'versions_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })
    package_metadata = @ecosystem.package_metadata('base62')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.length, 16
    
    first_version = versions_metadata.find { |v| v[:number] == "0.1.0" }
    assert_equal first_version[:number], "0.1.0"
    assert_equal first_version[:published_at], "2012-02-24T18:04:06.916Z"
    assert_equal first_version[:licenses], ""
    assert_equal first_version[:integrity], "sha1-03b8bde71477f095dff3455ccd5f8e0fd6bf91fa"
    assert_nil first_version[:metadata][:deprecated]
    assert_equal first_version[:metadata]["_npmUser"], {"name"=>"andrewnez", "email"=>"andrewnez@gmail.com"}
    assert_equal first_version[:metadata]["engines"], {"node"=>"*"}
    assert_nil first_version[:metadata]["exports"]
    assert_nil first_version[:metadata]["browserify"]
  
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })
    package_metadata = @ecosystem.package_metadata('base62')
    dependencies_metadata = @ecosystem.dependencies_metadata('base62', '2.0.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"mocha", :requirements=>"~5.1.0", :kind=>"Development", :optional=>false, :ecosystem=>"npm"}
    ]
  end

  test 'maintainer_url' do
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://www.npmjs.com/~foo'
  end

  test 'fetch_download_counts bulk-fetches unscoped names' do
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62,express")
      .to_return(status: 200, body: '{"base62":{"downloads":10},"express":{"downloads":20}}', headers: { 'Content-Type' => 'application/json' })
    counts = @ecosystem.fetch_download_counts(['base62', 'express'])
    assert_equal({ 'base62' => 10, 'express' => 20 }, counts)
  end

  test 'fetch_download_counts fetches scoped names individually' do
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/lodash,express")
      .to_return(status: 200, body: '{"lodash":{"downloads":5},"express":{"downloads":6}}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/@scope/pkg")
      .to_return(status: 200, body: '{"downloads":7,"package":"@scope/pkg"}', headers: { 'Content-Type' => 'application/json' })
    counts = @ecosystem.fetch_download_counts(['@scope/pkg', 'lodash', 'express'])
    assert_equal 5, counts['lodash']
    assert_equal 6, counts['express']
    assert_equal 7, counts['@scope/pkg']
  end

  test 'fetch_download_counts slices unscoped names into batches of 128' do
    names = (1..130).map { |i| "pkg#{i}" }
    stub_request(:get, %r{https://api\.npmjs\.org/downloads/point/last-month/pkg1,.*,pkg128$})
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/pkg129,pkg130")
      .to_return(status: 200, body: '{"pkg129":{"downloads":1}}', headers: { 'Content-Type' => 'application/json' })
    counts = @ecosystem.fetch_download_counts(names)
    assert_equal 1, counts['pkg129']
  end

  test 'fetch_download_counts routes a lone unscoped name through the single-package path' do
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/lodash")
      .to_return(status: 200, body: '{"downloads":9,"package":"lodash"}', headers: { 'Content-Type' => 'application/json' })
    assert_equal({ 'lodash' => 9 }, @ecosystem.fetch_download_counts(['lodash']))
  end

  test 'fetch_download_counts routes a single-name trailing slice through the single-package path' do
    names = (1..129).map { |i| "pkg#{i}" }
    stub_request(:get, %r{https://api\.npmjs\.org/downloads/point/last-month/pkg1,.*,pkg128$})
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/pkg129")
      .to_return(status: 200, body: '{"downloads":3,"package":"pkg129"}', headers: { 'Content-Type' => 'application/json' })
    assert_equal 3, @ecosystem.fetch_download_counts(names)['pkg129']
  end

  test 'fetch_download_counts ignores non-hash bulk response' do
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/a,b")
      .to_return(status: 500, body: 'null', headers: { 'Content-Type' => 'application/json' })
    assert_equal({}, @ecosystem.fetch_download_counts(['a', 'b']))
  end

  test 'fetch_download_counts continues after a bulk request errors' do
    names = (1..130).map { |i| "pkg#{i}" }
    stub_request(:get, %r{https://api\.npmjs\.org/downloads/point/last-month/pkg1,.*,pkg128$})
      .to_return(status: 500, body: 'not json', headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/pkg129,pkg130")
      .to_return(status: 200, body: '{"pkg129":{"downloads":1}}', headers: { 'Content-Type' => 'application/json' })
    assert_equal 1, @ecosystem.fetch_download_counts(names)['pkg129']
  end

  test 'check_status uses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62.1') })

    # Fetch metadata first to populate the cache
    @ecosystem.package_metadata('base62')

    # check_status should reuse cached data, not make a new request
    status = @ecosystem.check_status(@package)
    assert_nil status # base62 is not deprecated/removed

    # The registry URL should only have been called once (for the initial fetch)
    assert_requested(:get, "https://registry.npmjs.org/base62", times: 1)
  end

  test 'versions_metadata includes npm specific fields for modern packages' do
    stub_request(:get, "https://registry.npmjs.org/react")
      .to_return({ status: 200, body: file_fixture('npm/react_fresh') })
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/react")
      .to_return({ status: 200, body: '{"downloads": 50000000}' })
    package_metadata = @ecosystem.package_metadata('react')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:metadata]["engines"], {"node" => ">=0.10.0"}
    assert_equal first_version[:metadata]["_nodeVersion"], "18.20.0"
    assert_equal first_version[:metadata]["_npmVersion"], "10.5.0"
    assert_equal first_version[:metadata]["exports"]["."]["default"], "./index.js"
    assert_equal first_version[:metadata]["browserify"]["transform"], ["loose-envify"]
    assert_equal first_version[:metadata]["contentPolicy"], {"class"=>"dual-use"}
    assert_equal package_metadata[:metadata]["contentPolicy"], {"class"=>"dual-use"}
  end
end
