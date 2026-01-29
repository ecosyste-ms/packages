require "test_helper"

class DebianTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'debian-12', version: '12', url: 'https://packages.debian.org/bookworm', ecosystem: 'debian', metadata: { 'codename' => 'bookworm' })
    @ecosystem = Ecosystem::Debian.new(@registry)
    @package = Package.new(ecosystem: 'debian', name: 'curl', metadata: { 'component' => 'main', 'architecture' => 'any' })
    @version = @package.versions.build(number: '7.88.1-10+deb12u8')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal 'https://tracker.debian.org/pkg/curl', registry_url
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal 'http://deb.debian.org/debian/pool/main/c/curl/curl_7.88.1-10+deb12u8.orig.tar.gz', download_url
  end

  test 'download_url for lib package' do
    lib_package = Package.new(ecosystem: 'debian', name: 'libreoffice', metadata: { 'component' => 'main' })
    lib_version = lib_package.versions.build(number: '7.4.7')
    download_url = @ecosystem.download_url(lib_package, lib_version)
    assert_equal 'http://deb.debian.org/debian/pool/main/libr/libreoffice/libreoffice_7.4.7.orig.tar.gz', download_url
  end

  test 'download_url without version returns nil' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_nil download_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal 'apt-get install curl', install_command
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:deb/debian/curl?arch=source&distro=debian-12', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:deb/debian/curl@7.88.1-10%2Bdeb12u8?arch=source&distro=debian-12', purl
    assert Purl.parse(purl)
  end

  test 'components' do
    assert_equal ['main', 'contrib', 'non-free', 'non-free-firmware'], @ecosystem.components
  end

  test 'mirror_url' do
    assert_equal 'http://deb.debian.org/debian', @ecosystem.mirror_url
  end

  test 'documentation_url' do
    doc_url = @ecosystem.documentation_url(@package)
    assert_equal 'https://packages.debian.org/bookworm/curl', doc_url
  end
end
