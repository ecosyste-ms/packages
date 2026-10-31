require "test_helper"

class OpenvsxTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'open-vsx.org', url: 'https://open-vsx.org', ecosystem: 'openvsx')
    @ecosystem = Ecosystem::Openvsx.new(@registry)
    @package = Package.new(ecosystem: 'Openvsx', namespace: 'redhat', name: 'redhat/vscode-yaml')
    @version = @package.versions.build(number: '1.18.0')
    @maintainer = @registry.maintainers.build(login: 'rhdevelopers-ci', name: 'Red Hat Developers CI', url: 'https://github.com/rhdevelopers-ci')
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

  test 'purl names the registry explicitly even for the default registry' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:vscode-extension/redhat/vscode-yaml?repository_url=https://open-vsx.org'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:vscode-extension/redhat/vscode-yaml@1.18.0?repository_url=https://open-vsx.org'
    assert Purl.parse(purl)
  end

  test 'purl type lookups support current and legacy types' do
    ['vscode-extension', 'openvsx'].each do |purl_type|
      assert_equal 'openvsx', Ecosystem::Base.purl_type_to_ecosystem(purl_type)
      assert_equal '/', Ecosystem::Base.purl_type_to_namespace_separator(purl_type)
    end
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
    assert_equal package_metadata[:namespace], "redhat"
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
    stub_request(:get, "https://open-vsx.org/api/redhat/vscode-yaml/1.18.0")
      .to_return({ status: 200, body: file_fixture('openvsx/vscode-yaml-1.18.0.json') })
    stub_request(:get, "https://open-vsx.org/api/redhat/vscode-yaml/1.18.0/file/redhat.vscode-yaml-1.18.0.sha256")
      .to_return(status: 200, body: "#{'A' * 64}\n")
    package_metadata = @ecosystem.package_metadata('redhat/vscode-yaml')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata[0], {
      number: "1.18.0",
      published_at: DateTime.parse("2025-04-28T15:41:07.089268Z"),
      status: nil,
      integrity: "sha256-#{'a' * 64}",
      metadata: {
        download_url: 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0/file/redhat.vscode-yaml-1.18.0.vsix',
        signature_url: 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0/file/redhat.vscode-yaml-1.18.0.sigzip',
        public_key_url: 'https://open-vsx.org/api/-/public-key/14ccb407-4e79-41ed-be5a-6d608325c45a',
        sha256_url: 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0/file/redhat.vscode-yaml-1.18.0.sha256',
        target_platform: 'universal',
        published_by: JSON.parse(file_fixture('openvsx/vscode-yaml-1.18.0.json').read)['publishedBy']
      }
    }
  end

  test 'registry sync persists security metadata for new platform versions only' do
    @registry = Registry.create!(name: 'open-vsx.org', url: 'https://open-vsx.org', ecosystem: 'openvsx')
    package = @registry.packages.create!(name: @package.name, ecosystem: 'openvsx')
    existing = package.versions.create!(number: '1.17.0', metadata: { 'keep' => true })
    source = JSON.parse(file_fixture('openvsx/vscode-yaml-1.18.0.json').read)
    source['allVersions'] = { 'latest' => 'unused', '1.18.0' => 'unused', '1.17.0' => 'unused' }
    source['targetPlatform'] = 'linux-x64'
    source['publishedWithTrustedPublishing'] = true
    source['files'].transform_values! { |url| url.sub('/1.18.0/file/', '/linux-x64/1.18.0/file/') }
    stub_request(:get, 'https://open-vsx.org/api/redhat/vscode-yaml')
      .to_return(status: 200, body: source.to_json)
    stub_request(:get, 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0')
      .to_return(status: 200, body: source.to_json)
    stub_request(:get, source['files']['sha256'])
      .to_return(status: 200, body: 'b' * 64)

    synced = @registry.sync_package(package.name)
    version = synced.versions.find_by!(number: '1.18.0').reload

    assert_equal "sha256-#{'b' * 64}", version.integrity
    assert_equal source['files']['download'], version.download_url
    assert_equal source['files']['signature'], version.metadata['signature_url']
    assert_equal source['files']['publicKey'], version.metadata['public_key_url']
    assert_equal source['files']['sha256'], version.metadata['sha256_url']
    assert_equal 'linux-x64', version.metadata['target_platform']
    assert_equal source['publishedBy'], version.metadata['published_by']
    assert_equal true, version.metadata['published_with_trusted_publishing']
    assert_equal({ 'keep' => true }, existing.reload.metadata)
    assert_nil existing.integrity
    assert_not_requested(:get, 'https://open-vsx.org/api/redhat/vscode-yaml/1.17.0')
    assert_requested(:get, source['files']['sha256'], times: 1)
  end

  test 'versions without optional security fields still import' do
    source = JSON.parse(file_fixture('openvsx/vscode-yaml-1.18.0.json').read)
    source.except!('files', 'publishedBy', 'targetPlatform')
    source['publishedWithTrustedPublishing'] = false
    source['downloadable'] = false
    stub_request(:get, 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0')
      .to_return(status: 200, body: source.to_json)

    version = @ecosystem.versions_metadata(name: @package.name, versions: { '1.18.0' => 'unused' }).sole

    assert_nil version[:integrity]
    assert_equal 'yanked', version[:status]
    assert_equal({ published_with_trusted_publishing: false }, version[:metadata])
  end

  test 'checksum failures do not discard version metadata' do
    source = JSON.parse(file_fixture('openvsx/vscode-yaml-1.18.0.json').read)
    stub_request(:get, 'https://open-vsx.org/api/redhat/vscode-yaml/1.18.0')
      .to_return(status: 200, body: source.to_json)
    checksum = stub_request(:get, source['files']['sha256'])
    checksum.to_return(status: 404, body: 'a' * 64)
      .then.to_return(status: 200, body: 'not a checksum')
      .then.to_return(status: 200, body: 'a' * 65)
      .then.to_timeout

    4.times do
      version = @ecosystem.versions_metadata(name: @package.name, versions: { '1.18.0' => 'unused' }).sole
      assert_equal '1.18.0', version[:number]
      assert_nil version[:integrity]
      assert_equal source['files']['signature'], version[:metadata][:signature_url]
    end
  end

  test 'maintainers_metadata' do
    stub_request(:get, "https://open-vsx.org/api/redhat/vscode-yaml")
      .to_return({ status: 200, body: file_fixture('openvsx/vscode-yaml.json') })
    maintainers_metadata = @ecosystem.maintainers_metadata('redhat/vscode-yaml')

    assert_equal maintainers_metadata[0], {
      uuid: 'rhdevelopers-ci',
      login: 'rhdevelopers-ci',
      name: 'Red Hat Developers CI',
      url: 'https://github.com/rhdevelopers-ci'
    }
    end

  test 'maintainer_url' do
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://github.com/rhdevelopers-ci'
  end

  test 'check_status reuses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://open-vsx.org/api/redhat/vscode-yaml")
      .to_return({ status: 200, body: file_fixture('openvsx/vscode-yaml.json') })

    # Fetch metadata first to populate the cache
    @ecosystem.package_metadata('redhat/vscode-yaml')

    # check_status should reuse cached data
    status = @ecosystem.check_status(@package)
    assert_nil status

    # The API should only have been called once (for the initial fetch)
    assert_requested(:get, "https://open-vsx.org/api/redhat/vscode-yaml", times: 1)
  end
end
