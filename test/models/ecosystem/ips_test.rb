require "test_helper"

class IpsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(
      default: true,
      name: 'openindiana-hipster',
      url: 'https://pkg.openindiana.org/hipster',
      ecosystem: 'ips',
      metadata: { 'publisher' => 'openindiana.org' }
    )
    @ecosystem = Ecosystem::Ips.new(@registry)
    @package = Package.new(ecosystem: 'ips', name: 'antivirus/clamav')
    @version = @package.versions.build(number: '1.5.1')
  end

  test 'registry_url without version' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal 'https://pkg.openindiana.org/hipster/en/search.shtml?token=antivirus/clamav&action=Search', registry_url
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal 'https://pkg.openindiana.org/hipster/en/info/0/antivirus/clamav@1.5.1', registry_url
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package)
    assert_equal 'https://pkg.openindiana.org/hipster/p5i/0/antivirus%2Fclamav.p5i', download_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal 'pkg install antivirus/clamav', install_command
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:ips/antivirus/clamav', purl
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:ips/antivirus/clamav@1.5.1', purl
  end

  test 'purl for package without namespace' do
    package = Package.new(ecosystem: 'ips', name: 'SUNWapch22')
    purl = @ecosystem.purl(package)
    assert_equal 'pkg:ips/SUNWapch22', purl
  end

  test 'purl for deeply nested package' do
    package = Package.new(ecosystem: 'ips', name: 'library/python/ipython')
    version = package.versions.build(number: '8.0.0')
    purl = @ecosystem.purl(package, version)
    assert_equal 'pkg:ips/library/python/ipython@8.0.0', purl
  end

  test 'human_version extracts component version' do
    assert_equal '1.5.1', @ecosystem.human_version('1.5.1,5.11-2025.0.0.0:20251029T172642Z')
    assert_equal '0.5.11', @ecosystem.human_version('0.5.11,5.11-0.175.0.0.0.0.0:20260127T062029Z')
    assert_nil @ecosystem.human_version(nil)
  end

  test 'published_at extracts timestamp' do
    result = @ecosystem.published_at('1.5.1,5.11-2025.0.0.0:20251029T172642Z')
    assert_equal 2025, result.year
    assert_equal 10, result.month
    assert_equal 29, result.day
  end

  test 'published_at returns nil for nil input' do
    assert_nil @ecosystem.published_at(nil)
  end

  test 'parse_actions extracts key-value pairs' do
    actions = [
      'set name=pkg.summary value="Implementation of an ICAP server"',
      'set name=pkg.human-version value=0.6.4',
      'set name=info.upstream-url value=https://c-icap.sourceforge.net/',
    ]
    result = @ecosystem.parse_actions(actions)
    assert_equal 'Implementation of an ICAP server', result['pkg.summary']
    assert_equal '0.6.4', result['pkg.human-version']
    assert_equal 'https://c-icap.sourceforge.net/', result['info.upstream-url']
  end

  test 'map_package_metadata' do
    pkg_metadata = {
      'name' => 'antivirus/clamav',
      'summary' => {
        'pkg.summary' => 'ClamAV opensource antivirus toolkit',
        'info.upstream-url' => 'https://www.clamav.net/',
        'info.source-url' => 'https://github.com/Cisco-Talos/clamav/archive/refs/tags/clamav-1.5.1.tar.gz',
        'info.classification' => 'org.opensolaris.category.2008:Applications/System Utilities',
        'pkg.human-version' => '1.5.1',
      },
      'versions' => [],
      'latest_version_string' => '1.5.1,5.11-2025.0.0.0:20251029T172642Z',
    }
    result = @ecosystem.map_package_metadata(pkg_metadata)
    assert_equal 'antivirus/clamav', result[:name]
    assert_equal 'ClamAV opensource antivirus toolkit', result[:description]
    assert_equal 'https://www.clamav.net/', result[:homepage]
    assert_equal '1.5.1', result[:metadata][:human_version]
    assert_equal 'antivirus', result[:namespace]
  end

  test 'map_package_metadata namespace for bare package name' do
    pkg_metadata = {
      'name' => 'SUNWapch22',
      'summary' => { 'pkg.summary' => 'Apache HTTP Server' },
      'versions' => [],
    }
    result = @ecosystem.map_package_metadata(pkg_metadata)
    assert_nil result[:namespace]
  end

  test 'versions_metadata' do
    @ecosystem.stubs(:fetch_package_metadata).with('antivirus/clamav').returns({
      'name' => 'antivirus/clamav',
      'versions' => [
        { 'version' => '1.4.3,5.11-2025.0.0.0:20250704T190629Z', 'signature-sha-1' => 'abc123' },
        { 'version' => '1.5.1,5.11-2025.0.0.0:20251029T172642Z', 'signature-sha-1' => 'def456' },
      ],
      'summary' => {},
    })
    result = @ecosystem.versions_metadata({ name: 'antivirus/clamav' })
    assert_equal 2, result.length
    assert_equal '1.4.3', result[0][:number]
    assert_equal 'sha1-abc123', result[0][:integrity]
    assert_equal '1.5.1', result[1][:number]
  end

  test 'dependencies_metadata parses require deps' do
    @ecosystem.instance_variable_set(:@dependency_packages, {
      'antivirus/c_icap' => [
        {
          'version' => '0.6.4,5.11-2026.0.0.1:20260225T211409Z',
          'actions' => [
            'depend fmri=pkg:/compress/bzip2@1.0.8-2022.1.0.1 type=require',
            'depend fmri=pkg:/library/security/openssl-3@3.5.1-2025.0.0.0 type=require',
            'set name=variant.arch value=i386',
          ]
        }
      ]
    })
    @ecosystem.stubs(:fetch_package_metadata).with('antivirus/c_icap').returns({
      'name' => 'antivirus/c_icap',
      'versions' => [
        { 'version' => '0.6.4,5.11-2026.0.0.1:20260225T211409Z', 'signature-sha-1' => 'abc' },
      ],
    })
    result = @ecosystem.dependencies_metadata('antivirus/c_icap', '0.6.4', nil)
    assert_equal 2, result.length
    assert_equal 'compress/bzip2', result[0][:package_name]
    assert_equal 'library/security/openssl-3', result[1][:package_name]
    assert_equal 'runtime', result[0][:kind]
    assert_equal 'ips', result[0][:ecosystem]
  end

  test 'dependencies_metadata skips obsolete packages' do
    @ecosystem.instance_variable_set(:@dependency_packages, {
      'old/package' => [
        {
          'version' => '1.0,5.11-2025.0.0.0:20250101T000000Z',
          'actions' => [
            'set name=pkg.obsolete value=true',
          ]
        }
      ]
    })
    @ecosystem.stubs(:fetch_package_metadata).with('old/package').returns({
      'name' => 'old/package',
      'versions' => [
        { 'version' => '1.0,5.11-2025.0.0.0:20250101T000000Z', 'signature-sha-1' => 'abc' },
      ],
    })
    result = @ecosystem.dependencies_metadata('old/package', '1.0', nil)
    assert_equal [], result
  end

  test 'check_status returns removed for missing package' do
    @ecosystem.stubs(:fetch_package_metadata).with('antivirus/clamav').returns(nil)
    assert_equal 'removed', @ecosystem.check_status(@package)
  end

  test 'catalog_url builds correct URL' do
    assert_equal 'https://pkg.openindiana.org/hipster/openindiana.org/catalog/1/catalog.base.C',
                 @ecosystem.catalog_url('catalog.base.C')
  end
end
