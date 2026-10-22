require "test_helper"

class SnapTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'snapcraft.io', url: 'https://snapcraft.io', ecosystem: 'snap')
    @ecosystem = Ecosystem::Snap.new(@registry)
    @package = Package.new(ecosystem: 'snap', name: 'gimp')
    @version = @package.versions.build(number: '3.2.4', metadata: { 'download_url' => 'https://api.snapcraft.io/api/v1/snaps/download/KDHYbyuzZukmLhiogKiUksByRhXD2gYV_560.snap' })
  end

  test 'registry_url' do
    assert_equal 'https://snapcraft.io/gimp', @ecosystem.registry_url(@package)
  end

  test 'install_command' do
    assert_equal 'snap install gimp', @ecosystem.install_command(@package)
  end

  test 'download_url' do
    assert_equal 'https://api.snapcraft.io/api/v1/snaps/download/KDHYbyuzZukmLhiogKiUksByRhXD2gYV_560.snap', @ecosystem.download_url(@package, @version)
    assert_nil @ecosystem.download_url(@package, nil)
  end

  test 'check_status_url' do
    assert_equal 'https://api.snapcraft.io/v2/snaps/info/gimp', @ecosystem.check_status_url(@package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:snap/gimp@3.2.4', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names from sitemap' do
    stub_request(:get, "https://snapcraft.io/store/sitemap.xml")
      .to_return({ status: 200, body: file_fixture('snap/sitemap.xml') })
    names = @ecosystem.all_package_names
    assert_equal %w[zoom-client spotify gimp jq], names
    refute_includes names, 'store'
    refute_includes names, 'some-post'
  end

  test 'recently_updated_package_names sorted by lastmod' do
    stub_request(:get, "https://snapcraft.io/store/sitemap.xml")
      .to_return({ status: 200, body: file_fixture('snap/sitemap.xml') })
    names = @ecosystem.recently_updated_package_names
    assert_equal %w[gimp spotify zoom-client jq], names
  end

  test 'package lists are empty when the sitemap errors' do
    stub_request(:get, "https://snapcraft.io/store/sitemap.xml")
      .to_return({ status: 504, body: '<html><body><h1>504 Gateway Time-out</h1></body></html>' })
    Rails.logger.expects(:warn).with('Snap package list unavailable: Snap sitemap returned 504').twice
    assert_equal [], @ecosystem.all_package_names
    assert_equal [], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata' do
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp\?fields=})
      .with(headers: { 'Snap-Device-Series' => '16' })
      .to_return({ status: 200, body: file_fixture('snap/info_gimp.json') })
    pkg = @ecosystem.package_metadata('gimp')

    assert_equal 'gimp', pkg[:name]
    assert_equal 'High-end image creation and manipulation', pkg[:description]
    assert_equal 'https://www.gimp.org/', pkg[:homepage]
    assert_equal 'GPL-3.0+ AND LGPL-3.0+', pkg[:licenses]
    assert_equal 'https://gitlab.gnome.org/GNOME/gimp/', pkg[:repository_url]
    assert_equal ['art-and-design'], pkg[:keywords_array]
    assert_equal 'gimp', pkg[:namespace]
    assert_equal 'GNU Image Manipulation Program', pkg[:metadata][:title]
    assert_equal 'KDHYbyuzZukmLhiogKiUksByRhXD2gYV', pkg[:metadata][:snap_id]
    assert_equal 'verified', pkg[:metadata][:publisher]['validation']
  end

  test 'package_metadata returns false when not found' do
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/nope\?fields=})
      .to_return({ status: 404, body: '{"error-list":[{"code":"resource-not-found","message":"No snap named"}]}' })
    assert_equal false, @ecosystem.package_metadata('nope')
  end

  test 'versions_metadata dedupes by version across architectures' do
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp\?fields=})
      .to_return({ status: 200, body: file_fixture('snap/info_gimp.json') })
    pkg = @ecosystem.package_metadata('gimp')
    versions = @ecosystem.versions_metadata(pkg)

    assert_equal 2, versions.length
    v = versions.find { |x| x[:number] == '3.2.4' }
    assert_equal '2026-04-17T10:00:55.957455+00:00', v[:published_at]
    assert_equal 560, v[:metadata][:revision]
    assert_equal 'core24', v[:metadata][:base]
    assert_equal 'strict', v[:metadata][:confinement]
    assert_equal 147214336, v[:metadata][:size]
    assert_equal %w[amd64 arm64], v[:metadata][:architectures]
    assert_equal ['stable'], v[:metadata][:channels]
    assert_match(/\Asha3-384-/, v[:integrity])

    rc = versions.find { |x| x[:number] == '3.2.0-RC3' }
    assert_equal ['preview/stable'], rc[:metadata][:channels]
  end

  test 'dependencies_metadata records base snap' do
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp\?fields=})
      .to_return({ status: 200, body: file_fixture('snap/info_gimp.json') })
    pkg = @ecosystem.package_metadata('gimp')
    deps = @ecosystem.dependencies_metadata('gimp', '3.2.4', pkg)

    assert_equal 1, deps.length
    assert_equal 'core24', deps.first[:package_name]
    assert_equal 'runtime', deps.first[:kind]
    assert_equal 'snap', deps.first[:ecosystem]
  end

  test 'dependencies_metadata empty for unknown version' do
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp\?fields=})
      .to_return({ status: 200, body: file_fixture('snap/info_gimp.json') })
    pkg = @ecosystem.package_metadata('gimp')
    assert_equal [], @ecosystem.dependencies_metadata('gimp', '0.0.1', pkg)
  end

  test 'maintainers_metadata' do
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp\?fields=})
      .to_return({ status: 200, body: file_fixture('snap/info_gimp.json') })
    maintainers = @ecosystem.maintainers_metadata('gimp')

    assert_equal 1, maintainers.length
    assert_equal 'gimp', maintainers.first[:login]
    assert_equal 'GIMP team', maintainers.first[:name]
    assert_equal 'KnkwCsgcmmqa9phHCWgT9XUaUYIdGsGk', maintainers.first[:uuid]
    assert_equal 'https://snapcraft.io/publisher/gimp', maintainers.first[:url]
  end

  test 'check_status removed for 404' do
    stub_request(:get, "https://api.snapcraft.io/v2/snaps/info/gone")
      .with(headers: { 'Snap-Device-Series' => '16' })
      .to_return({ status: 404, body: '{"error-list":[{"code":"resource-not-found"}]}' })
    assert_equal 'removed', @ecosystem.check_status(Package.new(name: 'gone'))
  end

  test 'check_status nil for 200' do
    stub_request(:get, "https://api.snapcraft.io/v2/snaps/info/gimp")
      .with(headers: { 'Snap-Device-Series' => '16' })
      .to_return({ status: 200, body: file_fixture('snap/info_gimp.json') })
    assert_nil @ecosystem.check_status(@package)
  end

  test 'has_dependent_repos' do
    refute @ecosystem.has_dependent_repos?
  end

  test 'sync_package persists releases, dependencies and publisher' do
    @registry.save!
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp\?fields=})
      .with(headers: { 'Snap-Device-Series' => '16' })
      .to_return(status: 200, body: file_fixture('snap/info_gimp.json'))
    stub_request(:get, 'https://api.snapcraft.io/v2/snaps/info/gimp')
      .with(headers: { 'Snap-Device-Series' => '16' })
      .to_return(status: 200, body: file_fixture('snap/info_gimp.json'))

    @registry.sync_package('gimp', force: true)
    package = @registry.packages.find_by!(name: 'gimp')
    assert_equal %w[3.2.0-RC3 3.2.4], package.versions.order(:number).pluck(:number)
    version = package.versions.find_by!(number: '3.2.4')
    assert_equal 'core24', version.metadata['base']
    assert_equal %w[amd64 arm64], version.metadata['architectures']
    assert_equal @version.metadata['download_url'], version.download_url
    assert_match(/\Asha3-384-/, version.integrity)
    assert_equal [['core24', '*', 'runtime', 'snap']], version.dependencies.pluck(:package_name, :requirements, :kind, :ecosystem)
    assert_equal ['gimp'], package.maintainers.pluck(:login)

    Registry.find(@registry.id).sync_package('gimp', force: true)
    assert_equal 2, package.versions.count
    assert_equal 1, version.dependencies.count
  end

  test 'sync_package refreshes channels when a version is promoted' do
    @registry.save!
    info = JSON.parse(file_fixture('snap/info_gimp.json').read)
    promoted = info.deep_dup
    promoted['channel-map'].each do |e|
      next unless e['version'] == '3.2.0-RC3'
      e['channel']['name'] = 'stable'
      e['revision'] += 100
    end
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp})
      .to_return({ status: 200, body: info.to_json }, { status: 200, body: info.to_json },
                 { status: 200, body: promoted.to_json })

    @registry.sync_package('gimp', force: true)
    version = @registry.packages.find_by!(name: 'gimp').versions.find_by!(number: '3.2.0-RC3')
    assert_equal ['preview/stable'], version.metadata['channels']

    Registry.find(@registry.id).sync_package('gimp', force: true)
    version.reload
    assert_equal ['stable'], version.metadata['channels']
    assert_equal 654, version.metadata['revision']
  end

  test 'sync_package clears channels for versions no longer released' do
    @registry.save!
    info = JSON.parse(file_fixture('snap/info_gimp.json').read)
    superseded = info.deep_dup
    superseded['channel-map'].reject! { |e| e['version'] == '3.2.0-RC3' }
    stub_request(:get, %r{\Ahttps://api\.snapcraft\.io/v2/snaps/info/gimp})
      .to_return({ status: 200, body: info.to_json }, { status: 200, body: info.to_json },
                 { status: 200, body: superseded.to_json })

    @registry.sync_package('gimp', force: true)
    Registry.find(@registry.id).sync_package('gimp', force: true)
    package = @registry.packages.find_by!(name: 'gimp')
    assert_equal [], package.versions.find_by!(number: '3.2.0-RC3').metadata['channels']
    assert_equal ['stable'], package.versions.find_by!(number: '3.2.4').metadata['channels']
  end

  test 'check_status preserves persisted status on unsuccessful responses' do
    @registry.save!
    package = @registry.packages.create!(name: 'gimp', ecosystem: 'snap', status: 'removed')
    [429, 500, 503].each do |status|
      stub_request(:get, 'https://api.snapcraft.io/v2/snaps/info/gimp')
        .to_return(status: status)
      package.check_status
      assert_equal 'removed', package.reload.status
    end
  end

  test 'check_status preserves persisted status on network failures' do
    @registry.save!
    package = @registry.packages.create!(name: 'gimp', ecosystem: 'snap', status: 'removed')
    stub_request(:get, 'https://api.snapcraft.io/v2/snaps/info/gimp').to_timeout
    package.check_status
    assert_equal 'removed', package.reload.status
  end

  test 'recent syncs respect the configured registry budget' do
    @registry.rate_limit = 1
    @registry.save!
    stub_request(:get, 'https://snapcraft.io/store/sitemap.xml')
      .to_return(status: 200, body: file_fixture('snap/sitemap.xml'))
    SyncPackageWorker.expects(:perform_bulk).with([[@registry.id, 'gimp', true], [@registry.id, 'spotify', true]])

    @registry.sync_recently_updated_packages_async(period: 2.seconds)
  end
end
