# frozen_string_literal: true

require 'test_helper'

class FreebsdTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(
      default: true,
      name: 'freebsd-14-amd64-latest',
      url: 'https://pkg.freebsd.org/FreeBSD%3A14%3Aamd64/latest',
      ecosystem: 'freebsd',
      github: 'freebsd'
    )
    @ecosystem = Ecosystem::Freebsd.new(@registry)
    @yaml_fixture = Rails.root.join('test/fixtures/files/freebsd/packagesite.yaml')

    @ecosystem.stubs(:packagesite_yaml_path).returns(@yaml_fixture.to_s)
  end

  test 'registry_url uses FreshPorts with origin metadata' do
    pkg = Package.new(
      ecosystem: 'freebsd',
      name: 'wget',
      metadata: { 'origin' => 'ftp/wget' }
    )

    assert_equal 'https://www.freshports.org/ftp/wget/', @ecosystem.registry_url(pkg)
  end

  test 'registry_url falls back to ports.cgi without origin' do
    pkg = Package.new(ecosystem: 'freebsd', name: 'wget')

    url = @ecosystem.registry_url(pkg)

    assert_includes url, 'ports.freebsd.org'
    assert_includes url, 'wget'
  end

  test 'download_url' do
    pkg = Package.new(
      ecosystem: 'freebsd',
      name: 'zsh-you-should-use',
      metadata: {
        'origin' => 'shells/zsh-you-should-use',
        'abi' => 'FreeBSD:14:amd64'
      }
    )
    version = pkg.versions.build(number: '1.10.0')

    expected = 'https://pkg.freebsd.org/FreeBSD%3A14%3Aamd64/latest/All/Hashed/zsh.pkg'

    assert_equal expected, @ecosystem.download_url(pkg, version)
  end

  test 'download_url returns nil without version' do
    pkg = Package.new(ecosystem: 'freebsd', name: 'zsh-you-should-use')

    assert_nil @ecosystem.download_url(pkg, nil)
  end

  test 'install_command' do
    pkg = Package.new(ecosystem: 'freebsd', name: 'nginx')

    assert_equal 'pkg install nginx', @ecosystem.install_command(pkg)
  end

  test 'all_package_names' do
    assert_equal(%w[aa-styled zsh-you-should-use].sort,
                 (@ecosystem.all_package_names & %w[aa-styled zsh-you-should-use]).sort)
  end

  test 'recently_updated_package_names favors latest build timestamps' do
    names = @ecosystem.recently_updated_package_names

    assert_includes names, 'zsh-you-should-use'
  end

  test 'map_package_metadata' do
    raw = {
      'name' => 'wget',
      'records' => [
        {
          'name' => 'wget',
          'origin' => 'ftp/wget',
          'version' => '1.25.0',
          'comment' => 'retrieve files',
          'maintainer' => 'Fred <fred@example.com>',
          'www' => 'https://www.gnu.org/s/wget/',
          'categories' => ['ftp'],
          'licenses' => ['GPLv3'],
          'abi' => 'FreeBSD:14:amd64',
          'desc' => 'Long text',
          'annotations' => { 'build_timestamp' => '2026-04-09T07:53:54+0000' },
          'deps' => {}
        }
      ]
    }

    mapped = @ecosystem.map_package_metadata(raw)

    assert_equal 'wget', mapped[:name]
    assert_equal 'retrieve files', mapped[:description]
    assert_equal 'https://www.gnu.org/s/wget/', mapped[:homepage]
    assert_equal 'ftp', mapped[:namespace]
    assert_equal 'GPLv3', mapped[:licenses]
    assert_equal 'ftp/wget', mapped.dig(:metadata, :origin)
  end

  test 'versions_metadata lists each package version once' do
    raw = @ecosystem.fetch_package_metadata_uncached('aa-styled')
    mapped = @ecosystem.map_package_metadata(raw)

    versions = @ecosystem.versions_metadata(mapped, [])

    assert_equal(%w[0.1.0 0.2.0].sort,
                 versions.map { |v| v[:number] }.sort)

    assert versions.all? { |v| v[:integrity].start_with?('sha256-') }
  end

  test 'dependencies_metadata maps pkg deps' do
    deps = @ecosystem.dependencies_metadata('zsh-you-should-use', '1.10.0', nil)

    assert_equal 1, deps.length
    assert_equal 'zsh', deps.first[:package_name]
    assert_equal '=5.9_5', deps.first[:requirements]
    assert_equal 'runtime', deps.first[:kind]
    assert_equal 'freebsd', deps.first[:ecosystem]
  end

  test 'maintainers_metadata parses Maintainer <email>' do
    fb = Ecosystem::Freebsd.new(@registry)
    fb.stubs(:fetch_package_metadata).with('wget').returns(
      'name' => 'wget',
      'records' => [{ 'maintainer' => 'Ada Lovelace <ada@example.com>' }]
    )

    rows = fb.maintainers_metadata('wget')

    assert_equal 'ada@example.com', rows.first[:uuid]
    assert_equal 'Ada Lovelace', rows.first[:name]
  end

  test 'maintainers_metadata handles bare email' do
    fb = Ecosystem::Freebsd.new(@registry)
    fb.stubs(:fetch_package_metadata).with('curl').returns(
      'name' => 'curl',
      'records' => [{ 'maintainer' => 'dev@example.com' }]
    )

    rows = fb.maintainers_metadata('curl')

    assert_equal 'dev@example.com', rows.first[:uuid]
  end

  test 'purl' do
    pkg = Package.new(
      ecosystem: 'freebsd',
      name: 'zsh-you-should-use',
      metadata: {
        'origin' => 'shells/zsh-you-should-use',
        'abi' => 'FreeBSD:14:amd64'
      }
    )

    purl_str = @ecosystem.purl(pkg)

    assert_match(%r{\Apkg:freebsd/shells/zsh-you-should-use(\?|$)}, purl_str)
    assert_includes(purl_str, 'abi')
    assert Purl.parse(purl_str), "invalid purl #{purl_str}"
  end

  test 'purl with version' do
    pkg = Package.new(
      ecosystem: 'freebsd',
      name: 'zsh-you-should-use',
      metadata: {
        'origin' => 'shells/zsh-you-should-use',
        'abi' => 'FreeBSD:14:amd64'
      }
    )

    purl_str = @ecosystem.purl(pkg, pkg.versions.build(number: '1.10.0'))

    assert_match(%r{@1\.10\.0}, purl_str)
    assert_match(%r{/shells/zsh-you-should-use}, purl_str)
    assert Purl.parse(purl_str), "invalid purl #{purl_str}"
  end

  test 'maintainer_url escapes query' do
    m = Maintainer.new(uuid: 'ada@example.com', name: 'Ada')

    url = @ecosystem.maintainer_url(m)

    assert_nil @ecosystem.maintainer_url(Maintainer.new(uuid: '', name: 'none'))
    assert_includes(url, '%40example.com')
  end

  test 'check_status removed when unknown package' do
    fb = Ecosystem::Freebsd.new(@registry)
    fb.stubs(:packagesite_yaml_path).returns(@yaml_fixture.to_s)
    fb.stubs(:fetch_package_metadata).with('nonexistent-package-xyz').returns(nil)

    pkg = Package.new(ecosystem: 'freebsd', name: 'nonexistent-package-xyz')

    assert_equal 'removed', fb.check_status(pkg)
  end
end
