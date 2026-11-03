require "test_helper"

class PostmarketosTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'postmarketOS v25.12', version: 'v25.12', url: 'https://pkgs.postmarketos.org', ecosystem: 'postmarketos')
    @ecosystem = Ecosystem::Postmarketos.new(@registry)
    @package = Package.new(ecosystem: 'postmarketos', name: 'postmarketos-mkinitfs', metadata: { 'architecture' => 'x86_64' })
    @version = @package.versions.build(number: '2.7.0-r0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://pkgs.postmarketos.org/package/v25.12/postmarketos/x86_64/postmarketos-mkinitfs'
  end

  test 'download_url with version' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://mirror.postmarketos.org/postmarketos/v25.12/x86_64/postmarketos-mkinitfs-2.7.0-r0.apk'
  end

  test 'download_url without version returns nil' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_nil download_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'apk add postmarketos-mkinitfs'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:apk/postmarketos/postmarketos-mkinitfs?arch=x86_64&distro=postmarketos-25.12'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:apk/postmarketos/postmarketos-mkinitfs@2.7.0-r0?arch=x86_64&distro=postmarketos-25.12'
    assert Purl.parse(purl)
  end

  test 'purl for a non-default registry excludes repository_url' do
    registry = Registry.new(default: false, url: 'https://pkgs.postmarketos.org/packages?branch=v25.12', version: 'v25.12')
    ecosystem = Ecosystem::Postmarketos.new(registry)

    assert_equal 'pkg:apk/postmarketos/postmarketos-mkinitfs?arch=x86_64&distro=postmarketos-25.12', ecosystem.purl(@package)
    assert_equal 'pkg:apk/postmarketos/postmarketos-mkinitfs@2.7.0-r0?arch=x86_64&distro=postmarketos-25.12', ecosystem.purl(@package, @version)
  end

  test 'purl for master preserves the rolling release name' do
    registry = Registry.new(default: false, url: 'https://pkgs.postmarketos.org/packages?branch=master', version: 'master')
    ecosystem = Ecosystem::Postmarketos.new(registry)

    assert_equal 'pkg:apk/postmarketos/postmarketos-mkinitfs?arch=x86_64&distro=postmarketos-master', ecosystem.purl(@package)
  end

  test 'purl for a registry without a version omits distro' do
    registry = Registry.new(default: false, url: 'https://pkgs.postmarketos.org')
    ecosystem = Ecosystem::Postmarketos.new(registry)

    assert_equal 'pkg:apk/postmarketos/postmarketos-mkinitfs?arch=x86_64', ecosystem.purl(@package)
  end

end
