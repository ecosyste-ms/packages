require "test_helper"

class DebSuitesTest < ActiveSupport::TestCase
  def sources_entry(version, build_depends: 'debhelper-compat (= 13)', directory: 'pool/main/o/openssl')
    <<~ENTRY
      Package: openssl
      Version: #{version}
      Directory: #{directory}
      Binary: openssl, libssl3
      Section: utils
      Homepage: https://www.openssl.org/
      Vcs-Browser: https://salsa.debian.org/debian/openssl
      Build-Depends: #{build_depends}
    ENTRY
  end

  def write_sources(dir, name, body, format)
    path = File.join(dir, name)
    case format
    when :gz then Zlib::GzipWriter.open(path) { |gz| gz.write(body) }
    when :xz
      File.write("#{path}.raw", body)
      system('xz', '--compress', '--stdout', "#{path}.raw", out: path, exception: true)
    end
    path
  end

  setup do
    @registry = Registry.create!(name: 'debian-12', version: '12', url: 'https://packages.debian.org/bookworm', ecosystem: 'debian', metadata: { 'codename' => 'bookworm' })
    @ecosystem = @registry.ecosystem_instance
  end

  test 'debian reads the release, updates and security suites' do
    assert_equal [
      { mirror: 'http://deb.debian.org/debian', suite: 'bookworm' },
      { mirror: 'http://deb.debian.org/debian', suite: 'bookworm-updates' },
      { mirror: 'http://security.debian.org/debian-security', suite: 'bookworm-security' }
    ], @ecosystem.suites
  end

  test 'archived debian releases use the archive security mirror and the old suite layout' do
    registry = Registry.new(name: 'debian-10', version: '10', ecosystem: 'debian', metadata: { 'codename' => 'buster', 'mirror' => 'http://archive.debian.org/debian' })

    assert_equal({ mirror: 'http://archive.debian.org/debian-security', suite: 'buster/updates' }, Ecosystem::Debian.new(registry).suites.last)
  end

  test 'ubuntu reads every suite from its own mirror' do
    registry = Registry.new(name: 'ubuntu-24.10', version: '24.10', ecosystem: 'ubuntu', metadata: { 'codename' => 'oracular', 'mirror' => 'http://old-releases.ubuntu.com/ubuntu' })

    assert_equal %w[oracular oracular-updates oracular-security], Ecosystem::Ubuntu.new(registry).suites.map { |suite| suite[:suite] }
    assert_equal ['http://old-releases.ubuntu.com/ubuntu'], Ecosystem::Ubuntu.new(registry).suites.map { |suite| suite[:mirror] }.uniq
  end

  test 'registry metadata can override the security mirror and suite' do
    registry = Registry.new(name: 'debian-12', ecosystem: 'debian', metadata: { 'codename' => 'bookworm', 'security_mirror' => 'http://mirror.example/debian-security', 'security_suite' => 'bookworm/updates' })

    assert_equal({ mirror: 'http://mirror.example/debian-security', suite: 'bookworm/updates' }, Ecosystem::Debian.new(registry).suites.last)
  end

  test 'parse_sources reads gzip and xz Sources files' do
    Dir.mktmpdir do |dir|
      gz = write_sources(dir, 'gz', sources_entry('3.0.20-1~deb12u2'), :gz)
      xz = write_sources(dir, 'xz', sources_entry('3.0.22-1~deb12u2'), :xz)

      assert_equal ['3.0.20-1~deb12u2'], @ecosystem.parse_sources(gz, 'main').map { |entry| entry[:version] }
      assert_equal ['3.0.22-1~deb12u2'], @ecosystem.parse_sources(xz, 'main').map { |entry| entry[:version] }
    end
  end

  test 'download_sources falls back to Sources.xz when a suite has no Sources.gz' do
    base = 'http://security.debian.org/debian-security/dists/bookworm-security/main/source/Sources'
    @ecosystem.expects(:download_and_cache).with("#{base}.gz", 'debian-bookworm-security-main').returns(nil)
    @ecosystem.expects(:download_and_cache).with("#{base}.xz", 'debian-bookworm-security-main').returns('/tmp/sources')

    assert_equal '/tmp/sources', @ecosystem.download_sources(@ecosystem.suites.last, 'main')
  end

  test 'packages_by_name keeps every version published across the suites and describes the package by the newest' do
    Dir.mktmpdir do |dir|
      files = {
        'bookworm' => write_sources(dir, 'main', sources_entry('3.0.20-1~deb12u2'), :gz),
        'bookworm-updates' => nil,
        'bookworm-security' => write_sources(dir, 'security', sources_entry('3.0.22-1~deb12u2', build_depends: 'debhelper-compat (= 13), perl:native',
                                                                            directory: 'pool/updates/main/o/openssl'), :xz)
      }
      @ecosystem.stubs(:components).returns(['main'])
      @ecosystem.stubs(:download_sources).with(has_entry(suite: 'bookworm'), 'main').returns(files['bookworm'])
      @ecosystem.stubs(:download_sources).with(has_entry(suite: 'bookworm-updates'), 'main').returns(nil)
      @ecosystem.stubs(:download_sources).with(has_entry(suite: 'bookworm-security'), 'main').returns(files['bookworm-security'])

      entry = @ecosystem.packages_by_name['openssl']

      assert_equal '3.0.22-1~deb12u2', entry[:version]
      assert_equal 'bookworm-security', entry[:suite]
      assert_equal [['3.0.20-1~deb12u2', 'bookworm'], ['3.0.22-1~deb12u2', 'bookworm-security']], entry[:versions].map { |v| [v[:number], v[:suite]] }

      versions = @ecosystem.versions_metadata({ name: 'openssl' }, [])
      assert_equal [['3.0.20-1~deb12u2', 'bookworm'], ['3.0.22-1~deb12u2', 'bookworm-security']], versions.map { |v| [v[:number], v[:metadata][:suite]] }
      assert_equal ['3.0.22-1~deb12u2'], @ecosystem.versions_metadata({ name: 'openssl' }, ['3.0.20-1~deb12u2']).map { |v| v[:number] }
      assert_equal %w[pool/main/o/openssl pool/updates/main/o/openssl], versions.map { |v| v[:metadata][:directory] }
      assert_equal ['openssl, libssl3', 'openssl, libssl3'], versions.map { |v| v[:metadata][:binary] }

      pkg_metadata = @ecosystem.map_package_metadata(entry)
      assert_equal %w[debhelper-compat], @ecosystem.dependencies_metadata('openssl', '3.0.20-1~deb12u2', pkg_metadata).map { |d| d[:package_name] }
      assert_equal %w[debhelper-compat perl:native], @ecosystem.dependencies_metadata('openssl', '3.0.22-1~deb12u2', pkg_metadata).map { |d| d[:package_name] }
    end
  end

  test 'download_url uses the security mirror and the pool directory of the suite the version came from' do
    package = Package.new(ecosystem: 'debian', name: 'openssl', metadata: { 'component' => 'main' })
    security = package.versions.build(number: '3.0.22-1~deb12u2', metadata: { 'suite' => 'bookworm-security', 'directory' => 'pool/updates/main/o/openssl' })
    release = package.versions.build(number: '3.0.20-1~deb12u2', metadata: { 'suite' => 'bookworm', 'directory' => 'pool/main/o/openssl' })

    assert_equal 'http://security.debian.org/debian-security/pool/updates/main/o/openssl/openssl_3.0.22-1~deb12u2.orig.tar.gz', @ecosystem.download_url(package, security)
    assert_equal 'http://deb.debian.org/debian/pool/main/o/openssl/openssl_3.0.20-1~deb12u2.orig.tar.gz', @ecosystem.download_url(package, release)
  end

  test 'download_url keeps the ubuntu pool layout for security versions' do
    registry = Registry.new(name: 'ubuntu-24.04', ecosystem: 'ubuntu', metadata: { 'codename' => 'noble' })
    package = Package.new(ecosystem: 'ubuntu', name: 'openssl', metadata: { 'component' => 'main' })
    version = package.versions.build(number: '3.0.13-0ubuntu3.16', metadata: { 'suite' => 'noble-security', 'directory' => 'pool/main/o/openssl' })

    assert_equal 'http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/openssl_3.0.13-0ubuntu3.16.orig.tar.gz', Ecosystem::Ubuntu.new(registry).download_url(package, version)
  end

  test 'legacy security and updates suites do not share a cache file' do
    registry = Registry.new(name: 'debian-10', version: '10', ecosystem: 'debian', metadata: { 'codename' => 'buster', 'mirror' => 'http://archive.debian.org/debian' })
    ecosystem = Ecosystem::Debian.new(registry)
    updates, security = ecosystem.suites.last(2)
    cache_dir = Rails.root.join('tmp', 'cache', 'ecosystems')
    keys = ['debian-buster-updates-main', 'debian-buster%2Fupdates-main']
    keys.each { |key| FileUtils.rm_f(cache_dir.join(key)) }
    ecosystem.stubs(:system).with('wget', '-q', '-P', anything, anything) do |_wget, _q, _p, dir, url|
      next false unless url.end_with?('.gz')
      Zlib::GzipWriter.open(File.join(dir, 'Sources.gz')) { |gz| gz.write(sources_entry(url.include?('debian-security') ? '1.1.1n-0+deb10u6' : '1.1.1n-0+deb10u3')) }
      true
    end.returns(true)

    assert_equal ['1.1.1n-0+deb10u3'], ecosystem.fetch_packages_for_component('main', suite: updates).map { |entry| entry[:version] }
    assert_equal ['1.1.1n-0+deb10u6'], ecosystem.fetch_packages_for_component('main', suite: security).map { |entry| entry[:version] }
    assert_equal ['buster/updates'], ecosystem.fetch_packages_for_component('main', suite: security).map { |entry| entry[:suite] }
  ensure
    keys&.each { |key| FileUtils.rm_f(cache_dir.join(key)) }
  end

  test 'parse_sources raises when xz fails part way through and the suite is skipped' do
    Dir.mktmpdir do |dir|
      xz = write_sources(dir, 'xz', sources_entry('3.0.22-1~deb12u2') * 200, :xz)
      File.truncate(xz, File.size(xz) - 40)

      assert_raises(Ecosystem::Deb::SourcesDecompressionError) { @ecosystem.parse_sources(xz, 'main') }

      @ecosystem.stubs(:download_sources).returns(xz)
      assert_equal [], @ecosystem.fetch_packages_for_component('main', suite: @ecosystem.suites.last)
    end
  end

  test 'syncing a package records the versions from every suite' do
    entry = { name: 'openssl', version: '3.0.22-1~deb12u2', suite: 'bookworm-security', homepage: 'https://www.openssl.org/',
              repository_url: 'https://salsa.debian.org/debian/openssl', section: 'utils', metadata: { component: 'main' },
              versions: [{ number: '3.0.20-1~deb12u2', suite: 'bookworm', metadata: { component: 'main' } },
                         { number: '3.0.22-1~deb12u2', suite: 'bookworm-security', metadata: { component: 'main' } }] }
    @ecosystem.instance_variable_set(:@packages_by_name, { 'openssl' => entry })
    @registry.stubs(:ecosystem_instance).returns(@ecosystem)
    Package.any_instance.stubs(:update_repo_metadata_async)

    @registry.sync_package('openssl')

    package = @registry.packages.find_by!(name: 'openssl')
    assert_equal({ '3.0.20-1~deb12u2' => 'bookworm', '3.0.22-1~deb12u2' => 'bookworm-security' }, package.versions.to_h { |v| [v.number, v.metadata['suite']] })
    assert_equal '3.0.22-1~deb12u2', package.latest_release_number
  end
end
