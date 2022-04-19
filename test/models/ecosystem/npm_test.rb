require "test_helper"

class NpmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @ecosystem = Ecosystem::Npm.new(@registry.url)
    @package = Package.new(ecosystem: 'npm', name: 'base62')
    @version = @package.versions.build(number: '2.0.1')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://www.npmjs.com/package/base62'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'https://www.npmjs.com/package/base62/v/2.0.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, "https://registry.npmjs.org/base62/-/base62-2.0.1.tgz"
  end

  test 'download_url for namespaced packages' do
    download_url = @ecosystem.download_url('@digital-boss/n8n-nodes-mollie', '0.2.0')
    assert_equal download_url, "https://registry.npmjs.org/@digital-boss/n8n-nodes-mollie/-/n8n-nodes-mollie-0.2.0.tgz"
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
    assert_equal install_command, 'npm install base62'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'npm install base62@2.0.1'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://www.npmjs.com/package/base62"
  end

  test 'all_package_names' do
    stub_request(:get, "https://raw.githubusercontent.com/nice-registry/all-the-package-names/master/names.json")
      .to_return({ status: 200, body: file_fixture('npm/names.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 290
    assert_equal all_package_names.last, '03-creatfront'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://registry.npmjs.org/-/rss?descending=true&limit=50")
      .to_return({ status: 200, body: file_fixture('npm/new-rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 45
    assert_equal recently_updated_package_names.last, '@trafilea/afrodita-components'
  end

  test 'package_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    package_metadata = @ecosystem.package_metadata('base62')

    assert_equal package_metadata[:name], "base62"
    assert_equal package_metadata[:description], "JavaScript Base62 encode/decoder"
    assert_equal package_metadata[:homepage], "https://github.com/base62/base62.js"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/base62/base62.js"
    assert_equal package_metadata[:keywords_array], ["base-62", "encoder", "decoder"]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    package_metadata = @ecosystem.package_metadata('base62')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.1.0", :published_at=>"2012-02-24T18:04:06.916Z", :licenses=>""},
      {:number=>"0.1.1", :published_at=>"2012-12-09T05:11:27.662Z", :licenses=>""},
      {:number=>"0.1.2", :published_at=>"2014-07-15T21:24:45.597Z", :licenses=>""},
      {:number=>"1.0.0", :published_at=>"2014-10-11T07:22:23.512Z", :licenses=>"MIT"},
      {:number=>"1.1.0", :published_at=>"2015-02-23T09:52:54.646Z", :licenses=>"MIT"},
      {:number=>"1.1.1", :published_at=>"2016-04-14T21:55:22.812Z", :licenses=>"MIT"},
      {:number=>"1.1.2", :published_at=>"2016-11-14T00:43:51.131Z", :licenses=>"MIT"},
      {:number=>"1.2.0", :published_at=>"2017-05-15T11:26:01.056Z", :licenses=>"MIT"},
      {:number=>"1.2.1", :published_at=>"2017-11-14T08:38:56.587Z", :licenses=>"MIT"},
      {:number=>"1.2.4", :published_at=>"2018-02-10T21:54:23.964Z", :licenses=>"MIT"},
      {:number=>"1.2.5", :published_at=>"2018-02-10T23:16:39.461Z", :licenses=>"MIT"},
      {:number=>"1.2.6", :published_at=>"2018-02-14T12:24:12.680Z", :licenses=>"MIT"},
      {:number=>"1.2.7", :published_at=>"2018-02-14T12:46:17.280Z", :licenses=>"MIT"},
      {:number=>"1.2.8", :published_at=>"2018-03-30T17:15:14.729Z", :licenses=>"MIT"},
      {:number=>"2.0.0", :published_at=>"2018-04-13T09:18:23.449Z", :licenses=>"MIT"},
      {:number=>"2.0.1", :published_at=>"2019-03-06T15:06:40.387Z", :licenses=>"MIT"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://registry.npmjs.org/base62")
      .to_return({ status: 200, body: file_fixture('npm/base62') })
    package_metadata = @ecosystem.package_metadata('base62')
    dependencies_metadata = @ecosystem.dependencies_metadata('base62', '2.0.0', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"mocha", :requirements=>"~5.1.0", :kind=>"Development", :optional=>false, :ecosystem=>"npm"}
    ]
  end
end
