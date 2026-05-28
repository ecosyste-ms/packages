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
    assert_equal '2026-04-17T10:01:41.749811+00:00', v[:published_at]
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
end
