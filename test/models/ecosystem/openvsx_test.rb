require "test_helper"

class OpenvsxTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'open-vsx.org', url: 'https://open-vsx.org', ecosystem: 'openvsx')
    @ecosystem = Ecosystem::Openvsx.new(@registry)
    @package = Package.new(ecosystem: 'Openvsx', name: 'redhat/vscode-yaml')
    @version = @package.versions.build(number: '1.18.0')
    @maintainer = @registry.maintainers.build(login: 'redhat')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://open-vsx.org/extension/redhat/vscode-yaml/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://open-vsx.org/extension/redhat/vscode-yaml/1.18.0'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0/file/redhat.vscode-yaml-1.18.0.vsix'
  end
  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://open-vsx.org/api/redhat/vscode-yaml"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:openvsx/redhat/vscode-yaml'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:openvsx/redhat/vscode-yaml@1.18.0'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://open-vsx.org/api/-/query?includeAllVersions=false&offset=0&size=50")
      .to_return({ status: 200, body: file_fixture('openvsx/extensions.json') })
    stub_request(:get, "https://open-vsx.org/api/-/query?includeAllVersions=false&offset=50&size=50")
      .to_return({ status: 200, body: file_fixture('openvsx/extensions2.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 50
    assert_equal all_package_names.last, 'vscode/perl'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://open-vsx.org/api/-/search?size=50&offset=0&sortOrder=desc&sortBy=timestamp&includeAllVersions=false")
      .to_return({ status: 200, body: file_fixture('openvsx/recent.json') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 50
    assert_equal recently_updated_package_names.last, 'SylvianAI/sylvian'
  end

  test 'package_metadata' do
    stub_request(:get, "https://open-vsx.org/api/redhat/vscode-yaml")
      .to_return({ status: 200, body: file_fixture('openvsx/vscode-yaml.json') })
    package_metadata = @ecosystem.package_metadata('redhat/vscode-yaml')

    assert_equal package_metadata[:name], "redhat/vscode-yaml"
    assert_equal package_metadata[:description], "YAML Language Support by Red Hat, with built-in Kubernetes syntax support"
    assert_equal package_metadata[:homepage], "https://github.com/redhat-developer/vscode-yaml#readme"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/redhat-developer/vscode-yaml"
    assert_equal package_metadata[:keywords_array], ["autocompletion", "dockercompose", "github-actions-workflow", "kubernetes", "validation", "yaml"]
    assert_equal package_metadata[:downloads], 1524693
    assert_equal package_metadata[:downloads_period], 'total'
    assert_equal package_metadata[:metadata], {:categories=>["Programming Languages", "Linters", "Snippets", "Formatters"]}
  end

  test 'versions_metadata' do
    stub_request(:get, "https://open-vsx.org/api/redhat/vscode-yaml")
      .to_return({ status: 200, body: file_fixture('openvsx/vscode-yaml.json') })
    package_metadata = @ecosystem.package_metadata('redhat/vscode-yaml')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata[0], {:number=>"1.18.0"}
  end

  test 'maintainer_url' do
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://open-vsx.org/namespace/redhat'
  end
end
