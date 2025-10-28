require "test_helper"

class AdelieTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Adelie', url: 'https://pkg.adelielinux.org', ecosystem: 'adelie')
    @ecosystem = Ecosystem::Adelie.new(@registry)
    @package = Package.new(ecosystem: 'adelie', name: 'test-package', metadata: { 'repository' => 'system', 'architecture' => 'x86_64' })
  end

  test 'maintainers_metadata returns empty array when package not found' do
    maintainers = @ecosystem.maintainers_metadata('nonexistent-package')
    assert_equal [], maintainers
  end

  test 'dependencies_metadata returns empty array when package not found' do
    dependencies = @ecosystem.dependencies_metadata('nonexistent-package', nil, {})
    assert_equal [], dependencies
  end

  test 'versions_metadata returns empty array when package not found' do
    versions = @ecosystem.versions_metadata({ name: 'nonexistent-package' })
    assert_equal [], versions
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://pkg.adelielinux.org/current/test-package'
  end

  test 'download_url with version' do
    version = @package.versions.build(number: '1.0.0')
    download_url = @ecosystem.download_url(@package, version)
    assert_equal download_url, 'https://distfiles.adelielinux.org/adelie/current/system/x86_64/test-package-1.0.0.apk'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'apk add test-package'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:apk/adelie/test-package?arch=x86_64'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    version = @package.versions.build(number: '1.0.0')
    purl = @ecosystem.purl(@package, version)
    assert_equal purl, 'pkg:apk/adelie/test-package@1.0.0?arch=x86_64'
    assert Purl.parse(purl)
  end
end
