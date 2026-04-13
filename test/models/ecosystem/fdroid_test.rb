require "test_helper"

class FdroidTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'F-Droid', url: 'https://f-droid.org', ecosystem: 'fdroid')
    @ecosystem = Ecosystem::Fdroid.new(@registry)
    @package = Package.new(ecosystem: 'fdroid', name: 'org.andstatus.game2048')
    @version = @package.versions.build(number: '1.15.1', metadata: { 'apk_name' => 'org.andstatus.game2048_44.apk' })
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://f-droid.org/packages/org.andstatus.game2048'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'fdroidcl install org.andstatus.game2048'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:fdroid/org.andstatus.game2048'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:fdroid/org.andstatus.game2048@1.15.1'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://f-droid.org/repo/index-v1.json")
      .to_return({ status: 200, body: file_fixture('fdroid/index-v1.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 3
    assert_includes all_package_names, 'org.andstatus.game2048'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://f-droid.org/repo/index-v1.json")
      .to_return({ status: 200, body: file_fixture('fdroid/index-v1.json') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 3
    assert_equal recently_updated_package_names.first, 'org.secuso.privacyfriendly2048'
  end

  test 'package_metadata' do
    stub_request(:get, "https://f-droid.org/repo/index-v1.json")
      .to_return({ status: 200, body: file_fixture('fdroid/index-v1.json') })
    package_metadata = @ecosystem.package_metadata('org.andstatus.game2048')

    assert_equal package_metadata[:name], 'org.andstatus.game2048'
    assert_equal package_metadata[:licenses], 'Apache-2.0'
    assert_equal package_metadata[:repository_url], 'https://github.com/andstatus/game2048'
    assert_equal package_metadata[:namespace], 'AndStatus'
    assert_equal package_metadata[:keywords_array], ['Games']
  end

  test 'versions_metadata' do
    stub_request(:get, "https://f-droid.org/repo/index-v1.json")
      .to_return({ status: 200, body: file_fixture('fdroid/index-v1.json') })
    package_metadata = @ecosystem.package_metadata('org.andstatus.game2048')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.length, 3
    assert_equal versions_metadata.first[:number], '1.15.1'
    assert_equal versions_metadata.first[:metadata][:version_code], 44
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://f-droid.org/repo/org.andstatus.game2048_44.apk'
  end

  test 'download_url without version returns nil' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_nil download_url
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://f-droid.org/packages/org.andstatus.game2048'
  end

  test 'sync_in_batches' do
    assert @ecosystem.sync_in_batches?
  end

  test 'has_dependent_repos' do
    refute @ecosystem.has_dependent_repos?
  end
end
