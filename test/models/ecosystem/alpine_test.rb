require "test_helper"

class AlpineTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Alpine v3.21', version: 'v3.21', url: 'https://pkgs.alpinelinux.org', ecosystem: 'alpine')
    @ecosystem = Ecosystem::Alpine.new(@registry)
    @package = Package.new(ecosystem: 'alpine', name: 'nextcloud30-dashboard', metadata: { 'repository' => 'community', 'architecture' => 'x86_64' })
    @version = @package.versions.build(number: '30.0.0-r0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://pkgs.alpinelinux.org/package/v3.21/community/x86_64/nextcloud30-dashboard'
  end

  test 'download_url with version' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://dl-cdn.alpinelinux.org/alpine/v3.21/community/x86_64/nextcloud30-dashboard-30.0.0-r0.apk'
  end

  test 'download_url without version returns nil' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_nil download_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'apk add nextcloud30-dashboard'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:apk/alpine/nextcloud30-dashboard?arch=x86_64&distro=alpine-3.21'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:apk/alpine/nextcloud30-dashboard@30.0.0-r0?arch=x86_64&distro=alpine-3.21'
    assert Purl.parse(purl)
  end

  test 'purl for a non-default registry excludes repository_url' do
    registry = Registry.new(default: false, url: 'https://pkgs.alpinelinux.org/packages?branch=v3.19', version: 'v3.19')
    ecosystem = Ecosystem::Alpine.new(registry)

    assert_equal 'pkg:apk/alpine/nextcloud30-dashboard?arch=x86_64&distro=alpine-3.19', ecosystem.purl(@package)
    assert_equal 'pkg:apk/alpine/nextcloud30-dashboard@30.0.0-r0?arch=x86_64&distro=alpine-3.19', ecosystem.purl(@package, @version)
  end

  test 'purl for edge preserves the rolling release name' do
    registry = Registry.new(default: false, url: 'https://pkgs.alpinelinux.org/packages?branch=edge', version: 'edge')
    ecosystem = Ecosystem::Alpine.new(registry)

    assert_equal 'pkg:apk/alpine/nextcloud30-dashboard?arch=x86_64&distro=alpine-edge', ecosystem.purl(@package)
  end

  test 'purl for a registry without a version omits distro' do
    registry = Registry.new(default: false, url: 'https://pkgs.alpinelinux.org')
    ecosystem = Ecosystem::Alpine.new(registry)

    assert_equal 'pkg:apk/alpine/nextcloud30-dashboard?arch=x86_64', ecosystem.purl(@package)
  end

end
