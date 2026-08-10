require "test_helper"

class GoTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'Go')
    @ecosystem = Ecosystem::Go.new(@registry)
    @package = Package.new(ecosystem: 'Go', name: 'github.com/aws/smithy-go')
    @version = @package.versions.build(number: 'v1.11.1')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://pkg.go.dev/github.com/aws/smithy-go'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://pkg.go.dev/github.com/aws/smithy-go@v1.11.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://proxy.golang.org/github.com/aws/smithy-go/@v/v1.11.1.zip'
  end

  test 'download_url escapes uppercase version characters for the proxy' do
    version = @package.versions.build(number: 'v1.0.0-RC1')

    assert_equal 'https://proxy.golang.org/github.com/aws/smithy-go/@v/v1.0.0-!r!c1.zip',
      @ecosystem.download_url(@package, version)
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://pkg.go.dev/github.com/aws/smithy-go#section-documentation"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "https://pkg.go.dev/github.com/aws/smithy-go@v1.11.1#section-documentation"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'go get github.com/aws/smithy-go'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'go get github.com/aws/smithy-go@v1.11.1'
  end

  test 'check_status accepts a pseudo-version when the version list is empty' do
    registry = Registry.create!(name: 'Go status', url: 'https://go-status.example', ecosystem: 'Go')
    package = registry.packages.create!(name: 'example.com/pseudo-only', ecosystem: 'go')
    package.versions.create!(number: 'v0.0.0-20260810161643-097856497a66', registry: registry)
    ecosystem = Ecosystem::Go.new(registry)
    stub_request(:head, 'https://pkg.go.dev/example.com/pseudo-only').to_return(status: 404)
    stub_request(:get, 'https://go-status.example/example.com/pseudo-only/@v/list').to_return(status: 200, body: '')
    stub_request(:get, 'https://go-status.example/example.com/pseudo-only/@v/v0.0.0-20260810161643-097856497a66.info')
      .to_return(status: 200, body: '{}')

    assert_nil ecosystem.check_status(package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:golang/github.com/aws/smithy-go'
    assert Purl.parse(purl)
  end

  test 'non-github purl' do
    package = Package.new(ecosystem: 'Go', name: 'google.golang.org/genproto')
    purl = @ecosystem.purl(package)
    assert_equal purl, 'pkg:golang/google.golang.org/genproto'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:golang/github.com/aws/smithy-go@v1.11.1'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://index.golang.org/index")
      .to_return({ status: 200, body: file_fixture('go/index') })
    
    stub_request(:get, "https://index.golang.org/index?since=2019-04-18T02:07:41.336899Z")
      .to_return({ status: 200, body: file_fixture('go/index?since=2019-04-18T02:07:41.336899Z') })

    all_package_names = @ecosystem.all_package_names
  
    assert_equal all_package_names.length, 864
    assert_equal all_package_names.last, 'github.com/xenolf/lego'
  end

  test 'sync_missing_packages_async enqueues the latest indexed version for missing paths' do
    registry = Registry.create!(default: true, name: 'Go discovery', url: 'https://go-discovery.example', ecosystem: 'Go')
    registry.packages.create!(name: 'example.com/existing', ecosystem: 'go')
    cursor = {
      'timestamp' => '2026-08-09T00:00:00Z',
      'path' => 'example.com/cursor',
      'version' => 'v1.0.0'
    }
    registry.update!(metadata: { Ecosystem::Go::SYNC_MISSING_CURSOR_KEY => cursor })
    ecosystem = Ecosystem::Go.new(registry)
    body = [
      { 'Path' => 'example.com/cursor', 'Version' => 'v1.0.0', 'Timestamp' => '2026-08-09T00:00:00Z' },
      { 'Path' => 'example.com/existing', 'Version' => 'v1.1.0', 'Timestamp' => '2026-08-09T00:01:00Z' },
      { 'Path' => 'example.com/missing', 'Version' => 'v1.0.0', 'Timestamp' => '2026-08-09T00:02:00Z' },
      { 'Path' => 'example.com/missing', 'Version' => 'v1.1.0', 'Timestamp' => '2026-08-09T00:03:00Z' }
    ].map { |row| Oj.dump(row) }.join("\n")
    stub_request(:get, "https://index.golang.org/index?since=2026-08-09T00:00:00Z&limit=2000")
      .to_return(status: 200, body: body)
    SyncPackageVersionWorker.expects(:perform_bulk).with([
      [registry.id, 'example.com/missing', 'v1.1.0']
    ])

    assert_equal 1, ecosystem.sync_missing_packages_async
    assert_equal({
      'timestamp' => '2026-08-09T00:03:00Z',
      'path' => 'example.com/missing',
      'version' => 'v1.1.0'
    }, registry.reload.metadata[Ecosystem::Go::SYNC_MISSING_CURSOR_KEY])
  end

  test 'sync_missing_packages_async keeps the latest version across index pages' do
    registry = Registry.create!(default: true, name: 'Go paged discovery', url: 'https://go-paged-discovery.example', ecosystem: 'Go')
    ecosystem = Ecosystem::Go.new(registry)
    first_page = Ecosystem::Go::INDEX_PAGE_SIZE.times.map do |index|
      {
        'Path' => 'example.com/missing',
        'Version' => "v1.0.#{index}",
        'Timestamp' => (Time.utc(2026, 8, 9) + index.seconds).iso8601(9)
      }
    end
    last_row = {
      'Path' => 'example.com/missing',
      'Version' => 'v2.0.0',
      'Timestamp' => '2026-08-10T00:00:00Z'
    }
    ecosystem.stubs(:index_versions).returns(first_page, [last_row])
    SyncPackageVersionWorker.expects(:perform_bulk).with([
      [registry.id, 'example.com/missing', 'v2.0.0']
    ])

    assert_equal 1, ecosystem.sync_missing_packages_async
  end

  test 'sync_missing_packages_cursor starts one day ago' do
    travel_to Time.utc(2026, 8, 10, 12) do
      assert_equal({ 'timestamp' => '2026-08-09T12:00:00.000000000Z' }, @ecosystem.sync_missing_packages_cursor)
    end
  end

  test 'sync_missing_packages_async does not save its cursor when the index fails' do
    registry = Registry.create!(default: true, name: 'Go failed discovery', url: 'https://go-failed-discovery.example', ecosystem: 'Go')
    ecosystem = Ecosystem::Go.new(registry)
    stub_request(:get, %r{\Ahttps://index\.golang\.org/index\?.*\z})
      .to_return(status: 503, body: '')

    assert_equal 0, ecosystem.sync_missing_packages_async
    assert_nil registry.reload.metadata[Ecosystem::Go::SYNC_MISSING_CURSOR_KEY]
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://index.golang.org/index?since=#{Time.now.utc.beginning_of_day.to_fs(:iso8601)}")
      .to_return({ status: 200, body: file_fixture('go/index') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 864
    assert_equal recently_updated_package_names.last, 'github.com/xenolf/lego'
  end

  test 'package_metadata' do
    stub_request(:get, "https://pkg.go.dev/v1beta/module/github.com/aws/smithy-go?licenses=true")
      .to_return({ status: 200, body: file_fixture('go/api_module_smithy-go.json') })
    stub_request(:get, "https://pkg.go.dev/v1beta/package/github.com/aws/smithy-go")
      .to_return({ status: 200, body: file_fixture('go/api_package_smithy-go.json') })
    package_metadata = @ecosystem.package_metadata('github.com/aws/smithy-go')

    assert_equal package_metadata[:name], "github.com/aws/smithy-go"
    assert_equal package_metadata[:description], "Package smithy provides the core components for a Smithy SDK."
    assert_equal package_metadata[:homepage], "https://github.com/aws/smithy-go"
    assert_equal package_metadata[:licenses], "Apache-2.0"
    assert_equal package_metadata[:repository_url], "https://github.com/aws/smithy-go"
    assert_nil package_metadata[:keywords_array]
    assert_equal package_metadata[:namespace], "github.com/aws"
  end

  test 'package_metadata falls back to proxy when API misses' do
    stub_request(:get, "https://pkg.go.dev/v1beta/module/github.com/aws/smithy-go?licenses=true")
      .to_return({ status: 404, body: '{"code":404,"message":"not found"}' })
    stub_request(:get, "https://proxy.golang.org/github.com/aws/smithy-go/@v/list")
      .to_return({ status: 200, body: file_fixture('go/list') })
    package_metadata = @ecosystem.package_metadata('github.com/aws/smithy-go')

    assert_equal package_metadata[:name], "github.com/aws/smithy-go"
    assert_equal package_metadata[:repository_url], "https://github.com/aws/smithy-go"
  end

  test 'package_metadata rejects an indexed version with an alternative module path' do
    name = 'github.com/googlecloudplatform/professional-services/tools/lambda-compat'
    version = 'v0.0.0-20260810161643-097856497a66'
    stub_request(:get, "https://proxy.golang.org/#{name}/@v/#{version}.mod")
      .to_return(status: 200, body: "module github.com/GoogleCloudPlatform/professional-services/tools/lambda-compat\n")

    assert_equal false, @ecosystem.package_metadata(name, version: version)
  end

  test 'package_metadata accepts an exact indexed version when the version list is empty' do
    name = 'github.com/example/pseudo-only'
    version = 'v0.0.0-20260810161643-097856497a66'
    stub_request(:get, "https://proxy.golang.org/#{name}/@v/#{version}.mod")
      .to_return(status: 200, body: "module #{name}\n")
    stub_request(:get, "https://pkg.go.dev/v1beta/module/#{name}?licenses=true")
      .to_return(status: 404, body: '{"code":404,"message":"not found"}')

    package_metadata = @ecosystem.package_metadata(name, version: version)

    assert_equal name, package_metadata[:name]
    assert_equal version, package_metadata[:version]
    assert_equal "https://#{name}", package_metadata[:repository_url]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/github.com/aws/smithy-go?limit=1000")
      .to_return({ status: 200, body: file_fixture('go/api_versions_smithy-go.json') })

    versions_metadata = @ecosystem.versions_metadata({ name: 'github.com/aws/smithy-go' })

    assert_equal versions_metadata.length, 57
    assert_equal versions_metadata.first, { number: "v1.25.1", published_at: "2026-04-23T17:02:33Z", status: nil }
  end

  test 'versions_metadata skips existing versions but re-emits retracted ones' do
    body = Oj.dump({
      'items' => [
        { 'modulePath' => 'github.com/aws/smithy-go', 'version' => 'v1.0.0', 'commitTime' => '2021-01-01T00:00:00Z', 'retracted' => false, 'deprecated' => false },
        { 'modulePath' => 'github.com/aws/smithy-go', 'version' => 'v0.9.0', 'commitTime' => '2020-12-01T00:00:00Z', 'retracted' => true, 'deprecated' => false },
        { 'modulePath' => 'github.com/aws/smithy-go/v2', 'version' => 'v2.0.0', 'commitTime' => '2022-01-01T00:00:00Z', 'retracted' => false, 'deprecated' => false }
      ]
    })
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/github.com/aws/smithy-go?limit=1000")
      .to_return({ status: 200, body: body })

    versions_metadata = @ecosystem.versions_metadata({ name: 'github.com/aws/smithy-go' }, ['v1.0.0', 'v0.9.0'])

    assert_equal versions_metadata, [{ number: "v0.9.0", published_at: "2020-12-01T00:00:00Z", status: "retracted" }]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://proxy.golang.org/github.com/aws/smithy-go/@v/v1.9.0.mod")
      .to_return({ status: 200, body: file_fixture('go/v1.9.0.mod') })
    dependencies_metadata = @ecosystem.dependencies_metadata('github.com/aws/smithy-go', 'v1.9.0', nil)

    assert_equal dependencies_metadata, [{:package_name=>"github.com/google/go-cmp", :requirements=>"v0.5.4", :kind=>"runtime", :ecosystem=>"go"}]
  end

  test 'dependencies_metadata escapes uppercase version characters for the proxy' do
    version = 'v1.0.0-RC1'
    stub_request(:get, 'https://proxy.golang.org/github.com/aws/smithy-go/@v/v1.0.0-!r!c1.mod')
      .to_return(status: 200, body: file_fixture('go/v1.9.0.mod'))

    dependencies = @ecosystem.dependencies_metadata('github.com/aws/smithy-go', version, nil)

    assert_equal 'github.com/google/go-cmp', dependencies.first[:package_name]
  end

  test 'versions_metadata falls back to proxy when API misses' do
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/github.com/aws/smithy-go?limit=1000")
      .to_return({ status: 404, body: '{"code":404,"message":"not found"}' })
    stub_request(:get, "https://proxy.golang.org/github.com/aws/smithy-go/@v/list")
      .to_return({ status: 200, body: file_fixture('go/list') })
    stub_request(:get, "https://proxy.golang.org/github.com/aws/smithy-go/@v/v1.9.0.info")
      .to_return({ status: 200, body: file_fixture('go/v1.9.0.info') })

    versions_metadata = @ecosystem.versions_metadata({ name: 'github.com/aws/smithy-go' })

    assert_equal versions_metadata, [{ number: "v1.9.0", published_at: "2021-11-05T22:57:36Z", status: nil }]
  end

  test 'versions_metadata includes an indexed pseudo-version omitted from the version list' do
    name = 'example.com/pseudo-only'
    version = 'v0.0.0-20260810161643-097856497a66'
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/#{name}?limit=1000")
      .to_return(status: 404, body: '{"code":404,"message":"not found"}')
    stub_request(:get, "https://proxy.golang.org/#{name}/@v/list")
      .to_return(status: 200, body: '')
    stub_request(:get, "https://proxy.golang.org/#{name}/@v/#{version}.info")
      .to_return(status: 200, body: Oj.dump('Version' => version, 'Time' => '2026-08-10T16:16:43Z'))

    versions_metadata = @ecosystem.versions_metadata({ name: name, version: version })

    assert_equal [{ number: version, published_at: '2026-08-10T16:16:43Z', status: nil }], versions_metadata
  end
end
