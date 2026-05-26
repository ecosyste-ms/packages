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
end
