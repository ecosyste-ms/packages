# frozen_string_literal: true

require 'test_helper'

class EasybuildTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(
      default: true,
      name: 'docs.easybuild.io',
      url: 'https://docs.easybuild.io/version-specific/supported-software',
      ecosystem: 'easybuild'
    )
    @ecosystem = Ecosystem::Easybuild.new(@registry)
    @package = Package.new(ecosystem: 'easybuild', name: 'ABRicate')
    @digit_package = Package.new(ecosystem: 'easybuild', name: '2decomp-fft')
    @version = @package.versions.build(number: '1.0.0')
  end

  test 'registry_url' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/a/ABRicate/', @ecosystem.registry_url(@package)
  end

  test 'registry_url for package starting with digit' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/0/2decomp-fft/', @ecosystem.registry_url(@digit_package)
  end

  test 'install_command' do
    assert_equal 'eb ABRicate --robot', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'eb ABRicate-1.0.0.eb --robot', @ecosystem.install_command(@package, @version)
    assert_equal 'eb ABRicate-1.0.0.eb --robot', @ecosystem.install_command(@package, '1.0.0')
  end

  test 'check_status_url' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/a/ABRicate/', @ecosystem.check_status_url(@package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:easybuild/ABRicate', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:easybuild/ABRicate@1.0.0', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    html = <<~HTML
      <article>
        <ul>
          <li><a href="0/2decomp-fft/">2decomp-fft</a></li>
          <li><a href="a/ABRicate/">ABRicate</a></li>
          <li><a href="c/CMake/">CMake</a></li>
          <li><a href="../..">Back</a></li>
        </ul>
      </article>
    HTML

    stub_request(:get, 'https://docs.easybuild.io/version-specific/supported-software')
      .to_return(status: 200, body: html, headers: { 'Content-Type' => 'text/html' })

    names = @ecosystem.all_package_names
    assert_equal ['2decomp-fft', 'ABRicate', 'CMake'], names
  end

  test 'recently_updated_package_names' do
    atom_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <title>adding easyconfigs: Go-1.26.10.eb</title>
        </entry>
        <entry>
          <title>adding easyconfigs: LDC-1.43.0.eb, LDC-1.43.0-GCCcore-14.2.0.eb</title>
        </entry>
        <entry>
          <title>Merge pull request #27195 from Micket/20261018033935_new_pr_scikit-bio</title>
        </entry>
        <entry>
          <title>Merge pull request #27230 from Crivella/feature-julia_1.13.2</title>
        </entry>
      </feed>
    XML

    stub_request(:get, 'https://github.com/easybuilders/easybuild-easyconfigs/commits/develop.atom')
      .to_return(status: 200, body: atom_xml, headers: { 'Content-Type' => 'application/atom+xml' })

    names = @ecosystem.recently_updated_package_names
    assert_includes names, 'Go'
    assert_includes names, 'LDC'
    assert_includes names, 'scikit-bio'
    assert_includes names, 'julia'
  end

  test 'package_metadata' do
    package_html = <<~HTML
      <article>
        <h1>ABRicate</h1>
        <p>Mass screening of contigs for antimicrobial and virulence genes</p>
        <p><em>homepage</em>: <a href="https://github.com/tseemann/abricate">https://github.com/tseemann/abricate</a></p>
        <table>
          <thead>
            <tr><th>version</th><th>toolchain</th></tr>
          </thead>
          <tbody>
            <tr><td><code>1.0.0</code></td><td><code>gompi/2023a</code></td></tr>
            <tr><td><code>1.0.0</code></td><td><code>gompi/2023b</code></td></tr>
          </tbody>
        </table>
      </article>
    HTML

    stub_request(:get, 'https://docs.easybuild.io/version-specific/supported-software/a/ABRicate/')
      .to_return(status: 200, body: package_html, headers: { 'Content-Type' => 'text/html' })

    metadata = @ecosystem.package_metadata('ABRicate')
    assert_equal 'ABRicate', metadata[:name]
    assert_equal 'Mass screening of contigs for antimicrobial and virulence genes', metadata[:description]
    assert_equal 'https://github.com/tseemann/abricate', metadata[:homepage]
    assert_equal '1.0.0', metadata[:version]
    assert_equal 'https://github.com/tseemann/abricate', metadata[:repository_url]
    assert_equal 2, metadata[:versions].length
  end

  test 'versions_metadata' do
    pkg_metadata = {
      name: 'ABRicate',
      versions: [
        { 'version' => '1.0.0', 'toolchain' => 'gompi/2023a' },
        { 'version' => '1.0.0', 'toolchain' => 'gompi/2023b' },
        { 'version' => '0.9.8', 'toolchain' => 'foss/2022a' }
      ]
    }

    versions = @ecosystem.versions_metadata(pkg_metadata)
    assert_equal 2, versions.length
    assert_equal '1.0.0', versions[0][:number]
    assert_equal ['gompi/2023a', 'gompi/2023b'], versions[0][:metadata][:toolchains]
    assert_equal '0.9.8', versions[1][:number]
    assert_equal ['foss/2022a'], versions[1][:metadata][:toolchains]
  end

  test 'check_status returns nil when package exists' do
    package_html = '<article><h1>ABRicate</h1></article>'
    stub_request(:get, 'https://docs.easybuild.io/version-specific/supported-software/a/ABRicate/')
      .to_return(status: 200, body: package_html, headers: { 'Content-Type' => 'text/html' })

    assert_nil @ecosystem.check_status(@package)
  end

  test 'check_status returns removed when 404' do
    stub_request(:get, 'https://docs.easybuild.io/version-specific/supported-software/a/ABRicate/')
      .to_return(status: 404, body: '')
    stub_request(:head, 'https://docs.easybuild.io/version-specific/supported-software/a/ABRicate/')
      .to_return(status: 404, body: '')

    assert_equal 'removed', @ecosystem.check_status(@package)
  end
end
