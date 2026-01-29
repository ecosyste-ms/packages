require "test_helper"

class UbuntuTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'ubuntu-24.04', version: '24.04', url: 'https://launchpad.net/ubuntu/noble', ecosystem: 'ubuntu', metadata: { 'codename' => 'noble' })
    @ecosystem = Ecosystem::Ubuntu.new(@registry)
    @package = Package.new(ecosystem: 'ubuntu', name: 'aalib', metadata: { 'component' => 'main', 'architecture' => 'any' })
    @version = @package.versions.build(number: '1.4p5-51.1')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal 'https://launchpad.net/ubuntu/+source/aalib', registry_url
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal 'https://launchpad.net/ubuntu/+source/aalib/1.4p5-51.1', registry_url
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal 'http://archive.ubuntu.com/ubuntu/pool/main/a/aalib/aalib_1.4p5-51.1.orig.tar.gz', download_url
  end

  test 'download_url for lib package' do
    lib_package = Package.new(ecosystem: 'ubuntu', name: 'libreoffice', metadata: { 'component' => 'main' })
    lib_version = lib_package.versions.build(number: '24.2.2')
    download_url = @ecosystem.download_url(lib_package, lib_version)
    assert_equal 'http://archive.ubuntu.com/ubuntu/pool/main/libr/libreoffice/libreoffice_24.2.2.orig.tar.gz', download_url
  end

  test 'download_url without version returns nil' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_nil download_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal 'apt-get install aalib', install_command
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:deb/ubuntu/aalib?arch=source&distro=ubuntu-24.04', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:deb/ubuntu/aalib@1.4p5-51.1?arch=source&distro=ubuntu-24.04', purl
    assert Purl.parse(purl)
  end

  test 'parse_dependencies handles version constraints' do
    deps_string = "debhelper-compat (= 13), dpkg-dev (>= 1.14.9), libgpm-dev [linux-any], libncurses5-dev"
    deps = @ecosystem.parse_dependencies(deps_string, 'build')

    assert_equal 4, deps.length
    assert_equal 'debhelper-compat', deps[0][:package_name]
    assert_equal '= 13', deps[0][:requirements]
    assert_equal 'dpkg-dev', deps[1][:package_name]
    assert_equal '>= 1.14.9', deps[1][:requirements]
    assert_equal 'libgpm-dev', deps[2][:package_name]
    assert_equal '*', deps[2][:requirements]
  end

  test 'parse_dependencies strips build profile restrictions' do
    deps_string = "cmake (>= 3.5), googletest (>= 1.12) [!mipsel !ppc64] <!nocheck>"
    deps = @ecosystem.parse_dependencies(deps_string, 'build')

    assert_equal 2, deps.length
    # The <!nocheck> gets parsed as part of the dep but angle brackets are stripped
    assert_equal 'googletest', deps[1][:package_name]
    assert_equal '>= 1.12', deps[1][:requirements]
  end

  test 'parse_source_entry' do
    entry = <<~ENTRY
      Package: aalib
      Version: 1.4p5-51.1
      Section: libs
      Maintainer: Jonathan Carter <jcc@debian.org>
      Homepage: http://aa-project.sourceforge.net/aalib/
      Vcs-Browser: https://salsa.debian.org/debian/aalib
      Directory: pool/main/a/aalib
    ENTRY

    result = @ecosystem.parse_source_entry(entry, 'main')

    assert_equal 'aalib', result[:name]
    assert_equal '1.4p5-51.1', result[:version]
    assert_equal 'http://aa-project.sourceforge.net/aalib/', result[:homepage]
    assert_equal 'https://salsa.debian.org/debian/aalib', result[:repository_url]
    assert_equal 'libs', result[:section]
    assert_equal 'main', result[:metadata][:component]
  end

  test 'maintainers_metadata parses maintainer string' do
    @ecosystem.instance_variable_set(:@packages_by_name, {
      'aalib' => {
        name: 'aalib',
        metadata: { maintainer: 'Jonathan Carter <jcc@debian.org>' }
      }
    })

    maintainers = @ecosystem.maintainers_metadata('aalib')
    assert_equal 1, maintainers.length
    assert_equal 'Jonathan Carter', maintainers[0][:name]
    assert_equal 'jcc@debian.org', maintainers[0][:uuid]
  end

  test 'map_package_metadata returns expected format' do
    pkg_metadata = {
      name: 'aalib',
      homepage: 'http://aa-project.sourceforge.net/aalib/',
      repository_url: 'https://salsa.debian.org/debian/aalib',
      section: 'libs',
      metadata: { component: 'main', architecture: 'any' }
    }

    result = @ecosystem.map_package_metadata(pkg_metadata)

    assert_equal 'aalib', result[:name]
    assert_equal 'http://aa-project.sourceforge.net/aalib/', result[:homepage]
    assert_equal ['libs'], result[:keywords_array]
    assert_equal 'main', result[:namespace]
  end
end
