require "test_helper"

class ChocolateyTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'community.chocolatey.org', url: 'https://community.chocolatey.org', ecosystem: 'chocolatey')
    @ecosystem = Ecosystem::Chocolatey.new(@registry)
    @package = Package.new(ecosystem: 'chocolatey', name: 'git', metadata: { 'docs_url' => 'https://git-scm.com/doc' })
    @version = @package.versions.build(number: '2.54.0')
  end

  test 'registry_url' do
    assert_equal 'https://community.chocolatey.org/packages/git', @ecosystem.registry_url(@package)
    assert_equal 'https://community.chocolatey.org/packages/git/2.54.0', @ecosystem.registry_url(@package, @version)
  end

  test 'download_url' do
    assert_equal 'https://community.chocolatey.org/api/v2/package/git/2.54.0', @ecosystem.download_url(@package, @version)
    assert_nil @ecosystem.download_url(@package, nil)
  end

  test 'install_command' do
    assert_equal 'choco install git', @ecosystem.install_command(@package)
    assert_equal 'choco install git --version=2.54.0', @ecosystem.install_command(@package, @version)
  end

  test 'documentation_url' do
    assert_equal 'https://git-scm.com/doc', @ecosystem.documentation_url(@package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:chocolatey/git@2.54.0', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names follows next links' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/Packages()?$filter=IsLatestVersion&$select=Id")
      .to_return({ status: 200, body: file_fixture('chocolatey/packages_page1.xml') })
    stub_request(:get, "https://community.chocolatey.org/api/v2/Packages()?$filter=IsLatestVersion&$select=Id&$skiptoken='1','jq'")
      .to_return({ status: 200, body: file_fixture('chocolatey/packages_page2.xml') })
    names = @ecosystem.all_package_names
    assert_equal %w[0ad jq zoom], names
  end

  test 'all_package_names returns partial results on error' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/Packages()?$filter=IsLatestVersion&$select=Id")
      .to_return({ status: 200, body: file_fixture('chocolatey/packages_page1.xml') })
    stub_request(:get, "https://community.chocolatey.org/api/v2/Packages()?$filter=IsLatestVersion&$select=Id&$skiptoken='1','jq'")
      .to_raise(Faraday::ConnectionFailed.new('boom'))
    names = @ecosystem.all_package_names
    assert_equal %w[0ad jq], names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://feeds.feedburner.com/chocolatey")
      .to_return({ status: 200, body: file_fixture('chocolatey/feed.xml') })
    assert_equal %w[wwphone foldersizes jq], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='git'")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_git.xml') })
    pkg = @ecosystem.package_metadata('git')

    assert_equal 'git', pkg[:name]
    assert_equal 'Git is a distributed version control system.', pkg[:description]
    assert_equal 'https://git-for-windows.github.io/', pkg[:homepage]
    assert_equal 'https://github.com/git-for-windows/git', pkg[:repository_url]
    assert_equal %w[git vcs], pkg[:keywords_array]
    assert_equal 'http://www.gnu.org/licenses/old-licenses/gpl-2.0.html', pkg[:licenses]
    assert_equal 35821940, pkg[:downloads]
    assert_equal 'total', pkg[:downloads_period]
    assert_equal 'The Git Development Community', pkg[:namespace]
    assert_equal 'Git', pkg[:metadata][:title]
    assert_equal 'https://git-scm.com/doc', pkg[:metadata][:docs_url]
    assert_equal 'https://github.com/chocolatey-community/chocolatey-packages/tree/master/automatic/git', pkg[:metadata][:package_source_url]
    assert pkg[:metadata][:is_approved]
  end

  test 'package_metadata from real jq fixture' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='jq'")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_jq.xml') })
    stub_request(:get, %r{\Ahttps?://community\.chocolatey\.org/api/v2/FindPackagesById.*skiptoken})
      .to_return({ status: 200, body: file_fixture('chocolatey/find_empty.xml') })
    pkg = @ecosystem.package_metadata('jq')

    assert_equal 'jq', pkg[:name]
    assert_equal 11, pkg[:entries].length
    assert_includes pkg[:keywords_array], 'json'
    assert pkg[:downloads] > 1_000_000
  end

  test 'package_metadata returns false when not found' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='nope'")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_empty.xml') })
    assert_equal false, @ecosystem.package_metadata('nope')
  end

  test 'versions_metadata' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='git'")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_git.xml') })
    pkg = @ecosystem.package_metadata('git')
    versions = @ecosystem.versions_metadata(pkg)

    assert_equal 2, versions.length
    v = versions.find { |x| x[:number] == '2.54.0' }
    assert_equal '2026-04-01T10:00:00.000', v[:published_at]
    assert_equal 'sha512-ZmFrZWhhc2g=', v[:integrity]
    assert_equal 412055, v[:metadata][:downloads]
    assert_equal 5196, v[:metadata][:package_size]
    refute v[:metadata][:is_prerelease]
    assert_equal 'git.install:[2.54.0]:|chocolatey-core.extension:1.3.3:', v[:metadata][:dependencies]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='git'")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_git.xml') })
    pkg = @ecosystem.package_metadata('git')
    deps = @ecosystem.dependencies_metadata('git', '2.54.0', pkg)

    assert_equal 2, deps.length
    install = deps.find { |d| d[:package_name] == 'git.install' }
    assert_equal '[2.54.0]', install[:requirements]
    assert_equal 'runtime', install[:kind]
    assert_equal 'chocolatey', install[:ecosystem]
    ext = deps.find { |d| d[:package_name] == 'chocolatey-core.extension' }
    assert_equal '1.3.3', ext[:requirements]
  end

  test 'dependencies_metadata for version without entry' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='git'")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_git.xml') })
    pkg = @ecosystem.package_metadata('git')
    assert_equal [], @ecosystem.dependencies_metadata('git', '0.0.1', pkg)
  end

  test 'parse_dependencies handles empty and blank' do
    assert_equal [], @ecosystem.parse_dependencies(nil)
    assert_equal [], @ecosystem.parse_dependencies('')
  end

  test 'parse_dependencies handles missing range' do
    deps = @ecosystem.parse_dependencies('foo::|bar:1.0:net45')
    assert_equal 'foo', deps[0][:package_name]
    assert_equal '*', deps[0][:requirements]
    assert_equal 'bar', deps[1][:package_name]
    assert_equal '1.0', deps[1][:requirements]
  end

  test 'check_status removed when no entries' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='gone'&$top=1")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_empty.xml') })
    assert_equal 'removed', @ecosystem.check_status(Package.new(name: 'gone'))
  end

  test 'check_status nil when entries present' do
    stub_request(:get, "https://community.chocolatey.org/api/v2/FindPackagesById()?id='git'&$top=1")
      .to_return({ status: 200, body: file_fixture('chocolatey/find_git.xml') })
    assert_nil @ecosystem.check_status(Package.new(name: 'git'))
  end

  test 'has_dependent_repos' do
    refute @ecosystem.has_dependent_repos?
  end
end
