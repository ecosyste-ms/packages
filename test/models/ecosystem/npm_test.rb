require "test_helper"

class NpmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
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
    assert PackageURL.parse(purl)
  end

  test 'purl with namespace' do
    @package = Package.new(ecosystem: 'npm', name: '@fudge-ai/browser', namespace: 'fudge-ai')
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:npm/%40fudge-ai/browser'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:npm/base62@2.0.1'
    assert PackageURL.parse(purl)
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
    assert_equal package_metadata[:downloads], 1076972
    assert_equal package_metadata[:downloads_period], "last-month"
    assert_nil package_metadata[:namespace]
    assert_equal package_metadata[:metadata], {"funding"=>nil, "dist-tags"=>{"latest"=>"2.0.1"}}
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
  end
end
