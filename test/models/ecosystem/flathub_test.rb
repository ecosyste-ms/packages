require "test_helper"

class FlathubTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'flathub.org', url: 'https://flathub.org', ecosystem: 'flathub')
    @ecosystem = Ecosystem::Flathub.new(@registry)
    @package = Package.new(ecosystem: 'flathub', name: 'org.gimp.GIMP', metadata: { 'urls' => { 'help' => 'https://www.gimp.org/docs/' } })
    @version = @package.versions.build(number: '3.2.4')
  end

  test 'registry_url' do
    assert_equal 'https://flathub.org/apps/org.gimp.GIMP', @ecosystem.registry_url(@package)
  end

  test 'install_command' do
    assert_equal 'flatpak install flathub org.gimp.GIMP', @ecosystem.install_command(@package)
  end

  test 'documentation_url' do
    assert_equal 'https://www.gimp.org/docs/', @ecosystem.documentation_url(@package)
  end

  test 'check_status_url' do
    assert_equal 'https://flathub.org/api/v2/appstream/org.gimp.GIMP', @ecosystem.check_status_url(@package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:flatpak/org.gimp.GIMP', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:flatpak/org.gimp.GIMP@3.2.4', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://flathub.org/api/v2/appstream")
      .to_return({ status: 200, body: file_fixture('flathub/appstream') })
    all_package_names = @ecosystem.all_package_names
    assert_equal 5, all_package_names.length
    assert_includes all_package_names, 'org.gimp.GIMP'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://flathub.org/api/v2/collection/recently-updated?page=1&per_page=100")
      .to_return({ status: 200, body: file_fixture('flathub/recently-updated') })
    stub_request(:get, "https://flathub.org/api/v2/collection/recently-added?page=1&per_page=100")
      .to_return({ status: 200, body: file_fixture('flathub/recently-updated') })
    names = @ecosystem.recently_updated_package_names
    assert_equal 3, names.length
    assert_equal 'dev.nicx.mimick', names.first
  end

  test 'package_metadata' do
    stub_request(:get, "https://flathub.org/api/v2/appstream/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/org.gimp.GIMP') })
    stub_request(:get, "https://flathub.org/api/v2/stats/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/stats_org.gimp.GIMP') })
    package_metadata = @ecosystem.package_metadata('org.gimp.GIMP')

    assert_equal 'org.gimp.GIMP', package_metadata[:name]
    assert_equal 'High-end image creation and manipulation', package_metadata[:description]
    assert_equal 'https://www.gimp.org/', package_metadata[:homepage]
    assert_equal 'GPL-3.0+ AND LGPL-3.0+', package_metadata[:licenses]
    assert_equal 'https://gitlab.gnome.org/GNOME/gimp/', package_metadata[:repository_url]
    assert_equal 'The GIMP team', package_metadata[:namespace]
    assert_includes package_metadata[:keywords_array], 'Graphics'
    assert_includes package_metadata[:keywords_array], 'Photoshop'
    assert_equal 3534790, package_metadata[:downloads]
    assert_equal 'total', package_metadata[:downloads_period]
    assert_equal 'GNU Image Manipulation Program', package_metadata[:metadata][:display_name]
    assert_equal 'org.gnome.Platform/x86_64/50', package_metadata[:metadata][:runtime]
    assert package_metadata[:metadata][:verified]
    assert_equal 72565, package_metadata[:metadata][:installs_last_month]
  end

  test 'package_metadata for missing package returns false' do
    stub_request(:get, "https://flathub.org/api/v2/appstream/does.not.exist")
      .to_return({ status: 404, body: '{"detail":"Not Found"}' })
    assert_equal false, @ecosystem.package_metadata('does.not.exist')
  end

  test 'versions_metadata' do
    stub_request(:get, "https://flathub.org/api/v2/appstream/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/org.gimp.GIMP') })
    stub_request(:get, "https://flathub.org/api/v2/stats/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/stats_org.gimp.GIMP') })
    package_metadata = @ecosystem.package_metadata('org.gimp.GIMP')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal 2, versions_metadata.length
    assert_equal '3.2.4', versions_metadata.first[:number]
    assert_equal Time.at(1776384000), versions_metadata.first[:published_at]
    assert_equal 'stable', versions_metadata.first[:metadata][:release_type]
    assert_equal 'https://www.gimp.org/release/3.2.4/', versions_metadata.first[:metadata][:url]
  end

  test 'dependencies_metadata for latest version' do
    stub_request(:get, "https://flathub.org/api/v2/appstream/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/org.gimp.GIMP') })
    stub_request(:get, "https://flathub.org/api/v2/stats/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/stats_org.gimp.GIMP') })
    package_metadata = @ecosystem.package_metadata('org.gimp.GIMP')
    deps = @ecosystem.dependencies_metadata('org.gimp.GIMP', '3.2.4', package_metadata)

    assert_equal 2, deps.length
    runtime = deps.find { |d| d[:kind] == 'runtime' }
    assert_equal 'org.gnome.Platform', runtime[:package_name]
    assert_equal '50', runtime[:requirements]
    assert_equal 'flathub', runtime[:ecosystem]
    sdk = deps.find { |d| d[:kind] == 'build' }
    assert_equal 'org.gnome.Sdk', sdk[:package_name]
  end

  test 'dependencies_metadata for older version is empty' do
    stub_request(:get, "https://flathub.org/api/v2/appstream/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/org.gimp.GIMP') })
    stub_request(:get, "https://flathub.org/api/v2/stats/org.gimp.GIMP")
      .to_return({ status: 200, body: file_fixture('flathub/stats_org.gimp.GIMP') })
    package_metadata = @ecosystem.package_metadata('org.gimp.GIMP')
    assert_equal [], @ecosystem.dependencies_metadata('org.gimp.GIMP', '3.2.2', package_metadata)
  end

  test 'has_dependent_repos' do
    refute @ecosystem.has_dependent_repos?
  end
end
