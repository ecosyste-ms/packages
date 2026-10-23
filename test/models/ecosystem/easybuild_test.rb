# frozen_string_literal: true

require 'test_helper'

class EasybuildTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'docs.easybuild.io', url: 'https://docs.easybuild.io', ecosystem: 'easybuild')
    @ecosystem = Ecosystem::Easybuild.new(@registry)
    @package = Package.new(ecosystem: 'easybuild', name: 'TensorFlow')
    @version = @package.versions.build(number: '2.13.0')
    @package_digit = Package.new(ecosystem: 'easybuild', name: '2decomp-fft')
  end

  test 'registry_url' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/t/TensorFlow/', @ecosystem.registry_url(@package)
  end

  test 'registry_url with version' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/t/TensorFlow/', @ecosystem.registry_url(@package, @version)
  end

  test 'registry_url for package starting with digit' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/0/2decomp-fft/', @ecosystem.registry_url(@package_digit)
  end

  test 'install_command' do
    assert_equal 'eb TensorFlow --robot', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'eb TensorFlow-2.13.0.eb --robot', @ecosystem.install_command(@package, @version.number)
  end

  test 'download_url' do
    assert_equal 'https://raw.githubusercontent.com/easybuilders/easybuild-easyconfigs/develop/easybuild/easyconfigs/t/TensorFlow/TensorFlow-2.13.0.eb', @ecosystem.download_url(@package, @version)
  end

  test 'download_url without version' do
    assert_nil @ecosystem.download_url(@package)
  end

  test 'purl' do
    assert_equal 'pkg:easybuild/TensorFlow', @ecosystem.purl(@package)
  end

  test 'purl with version' do
    assert_equal 'pkg:easybuild/TensorFlow@2.13.0', @ecosystem.purl(@package, @version)
  end

  test 'check_status_url' do
    assert_equal 'https://docs.easybuild.io/version-specific/supported-software/t/TensorFlow/', @ecosystem.check_status_url(@package)
  end

  test 'all_package_names' do
    html = <<~HTML
      <article class="md-content__inner md-typeset">
        <ul>
          <li><a href="0/2decomp-fft/">2decomp-fft</a></li>
          <li><a href="t/TensorFlow/">TensorFlow</a></li>
          <li><a href="z/zlib/">zlib</a></li>
        </ul>
      </article>
    HTML
    stub_request(:get, 'https://docs.easybuild.io/version-specific/supported-software/')
      .to_return(status: 200, body: html)

    names = @ecosystem.all_package_names
    assert_equal ['2decomp-fft', 'TensorFlow', 'zlib'], names
  end

  test 'recently_updated_package_names' do
    atom = <<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <title>adding easyconfigs: TensorFlow-2.13.0-foss-2023a.eb</title>
        </entry>
        <entry>
          <title>Merge pull request #123 from boegel/new_pr_zlib</title>
        </entry>
      </feed>
    XML
    stub_request(:get, 'https://github.com/easybuilders/easybuild-easyconfigs/commits/develop.atom')
      .to_return(status: 200, body: atom)

    names = @ecosystem.recently_updated_package_names
    assert_equal ['TensorFlow', 'zlib'], names
  end

  test 'fetch_package_metadata_uncached' do
    html = <<~HTML
      <article class="md-content__inner md-typeset">
        <h1>TensorFlow &para;</h1>
        <p>An open-source software library for Machine Intelligence</p>
        <p>homepage : https://www.tensorflow.org/</p>
        <table>
          <thead>
            <tr><th>version</th><th>toolchain</th></tr>
          </thead>
          <tbody>
            <tr><td><code>2.11.0</code></td><td><code>foss/2022a</code></td></tr>
            <tr><td><code>2.13.0</code></td><td><code>foss/2023a</code></td></tr>
          </tbody>
        </table>
      </article>
    HTML
    stub_request(:get, 'https://docs.easybuild.io/version-specific/supported-software/t/TensorFlow/')
      .to_return(status: 200, body: html)

    data = @ecosystem.fetch_package_metadata_uncached('TensorFlow')
    assert_equal 'TensorFlow', data[:name]
    assert_equal 'https://www.tensorflow.org/', data[:homepage]
    assert_equal 'An open-source software library for Machine Intelligence', data[:description]
    assert_equal ['2.11.0', '2.13.0'], data[:versions]
    assert_equal '2.13.0', data[:version]
  end

  test 'versions_metadata' do
    pkg_meta = {
      name: 'TensorFlow',
      versions: ['2.11.0', '2.13.0'],
      versions_detail: [
        { version: '2.11.0', toolchain: 'foss/2022a' },
        { version: '2.13.0', toolchain: 'foss/2023a' }
      ]
    }

    versions = @ecosystem.versions_metadata(pkg_meta)
    assert_equal 2, versions.length
    assert_equal '2.11.0', versions[0][:number]
    assert_equal ['foss/2022a'], versions[0][:metadata][:toolchains]
    assert_equal '2.13.0', versions[1][:number]
    assert_equal ['foss/2023a'], versions[1][:metadata][:toolchains]
  end

  test 'dependencies_metadata' do
    eb_content = <<~EB
      name = 'TensorFlow'
      version = '2.13.0'
      dependencies = [
          ('Python', '3.11.3'),
          ('h5py', '3.9.0')
      ]
    EB
    stub_request(:get, 'https://raw.githubusercontent.com/easybuilders/easybuild-easyconfigs/develop/easybuild/easyconfigs/t/TensorFlow/TensorFlow-2.13.0.eb')
      .to_return(status: 200, body: eb_content)

    deps = @ecosystem.dependencies_metadata('TensorFlow', '2.13.0')
    assert_equal 2, deps.length
    assert_equal 'Python', deps[0][:package_name]
    assert_equal '3.11.3', deps[0][:requirements]
    assert_equal 'runtime', deps[0][:kind]
    assert_equal 'easybuild', deps[0][:ecosystem]
  end
end
