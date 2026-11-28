require "test_helper"

class PurlVersionLookupDebTest < ActiveSupport::TestCase
  setup do
    @bookworm = Registry.create!(name: 'debian-12', version: '12', url: 'https://packages.debian.org/bookworm', ecosystem: 'debian', metadata: { 'codename' => 'bookworm' })
    @trixie = Registry.create!(name: 'debian-13', version: '13', url: 'https://packages.debian.org/trixie', ecosystem: 'debian', metadata: { 'codename' => 'trixie' })
    @openssl = @bookworm.packages.create!(name: 'openssl', ecosystem: 'debian',
                                          metadata: { 'binary' => 'openssl, libssl3, libssl-dev, libssl-doc, openssl-provider-legacy' })
    @release = @openssl.versions.create!(number: '3.0.20-1~deb12u2', registry: @bookworm, metadata: { 'suite' => 'bookworm' })
    @security = @openssl.versions.create!(number: '3.0.22-1~deb12u2', registry: @bookworm, metadata: { 'suite' => 'bookworm-security' })
    @postgresql = @bookworm.packages.create!(name: 'postgresql-15', ecosystem: 'debian', metadata: { 'binary' => 'postgresql-15, postgresql-client-15' })
    @postgresql.versions.create!(number: '15.3-0+deb12u1', registry: @bookworm)
  end

  def lookup(purl)
    PurlVersionLookup.new(purl).call
  end

  test 'matches a source package directly' do
    result = lookup('pkg:deb/debian/openssl@3.0.22-1~deb12u2?arch=source&distro=debian-12')

    assert_equal 'matched', result.match_status
    assert_equal @security, result.version
  end

  test 'resolves a binary package through the upstream qualifier' do
    result = lookup('pkg:deb/debian/libssl3@3.0.22-1~deb12u2?arch=amd64&distro=debian-12.7&upstream=openssl')

    assert_equal 'matched', result.match_status
    assert_equal @security, result.version
  end

  test 'uses the source version from the upstream qualifier when the binary version differs' do
    result = lookup('pkg:deb/debian/libssl3@3.0.20-1~deb12u2+b1?arch=amd64&distro=debian-12&upstream=openssl%403.0.20-1~deb12u2')

    assert_equal 'matched', result.match_status
    assert_equal @release, result.version
  end

  test 'resolves a binary package through the Binary field without an upstream qualifier' do
    result = lookup('pkg:deb/debian/libssl-dev@3.0.20-1~deb12u2?arch=amd64&distro=debian-12')

    assert_equal 'matched', result.match_status
    assert_equal @release, result.version
  end

  test 'matches a binNMU version to the source version it was rebuilt from' do
    result = lookup('pkg:deb/debian/libssl3@3.0.22-1~deb12u2%2Bb2?arch=amd64&distro=debian-12')

    assert_equal 'matched', result.match_status
    assert_equal @security, result.version
  end

  test 'matches an encoded plus in a deb version' do
    assert_equal 'matched', lookup('pkg:deb/debian/postgresql-15@15.3-0%2Bdeb12u1?distro=debian-12').match_status
  end

  test 'reads an unencoded plus in a deb version as a plus' do
    # purl 1.8.1 decodes a literal + as a space; fixed on purl main (fa6fdbf) and runs once the gem is bumped
    skip 'needs a purl release that keeps literal plus signs' if Purl.parse('pkg:deb/debian/a@1+b').version.include?(' ')

    assert_equal @security, lookup('pkg:deb/debian/libssl3@3.0.22-1~deb12u2+b2?arch=amd64&distro=debian-12').version
    assert_equal 'matched', lookup('pkg:deb/debian/postgresql-15@15.3-0+deb12u1?distro=debian-12').match_status
  end

  test 'the Binary field lookup can use the binary names index' do
    sql = Package.where("(packages.metadata->>'binary') IS NOT NULL")
                 .where("#{PurlVersionLookup::BINARY_NAMES_SQL} @> ARRAY[?]::text[]", 'libssl3').to_sql
    plan = Package.transaction do
      Package.connection.execute('SET LOCAL enable_seqscan = off')
      Package.connection.select_values("EXPLAIN #{sql}").join("\n")
    end

    assert_includes plan, 'index_packages_on_binary_names'
  end

  test 'does not resolve an explicit source purl through the binary fallback' do
    assert_equal 'missing', lookup('pkg:deb/debian/openssl@3.0.22-1~deb12u2%2Bb2?arch=source&distro=debian-12').match_status
    assert_equal 'matched', lookup('pkg:deb/debian/openssl@3.0.22-1~deb12u2%2Bb2?arch=amd64&distro=debian-12').match_status
  end

  test 'matches only the source version given in the upstream qualifier' do
    result = lookup('pkg:deb/debian/libssl3@3.0.22-1~deb12u2?arch=amd64&distro=debian-12&upstream=openssl%403.0.20-1~deb12u2')

    assert_equal 'matched', result.match_status
    assert_equal @release, result.version
  end

  test 'does not match a binary that the matched source version did not build' do
    tool = @bookworm.packages.create!(name: 'tool-src', ecosystem: 'debian', metadata: { 'binary' => 'tool, tool-extra' })
    tool.versions.create!(number: '1.0-1', registry: @bookworm, metadata: { 'binary' => 'tool' })
    tool.versions.create!(number: '1.1-1', registry: @bookworm, metadata: { 'binary' => 'tool, tool-extra' })
    tool.versions.create!(number: '0.9-1', registry: @bookworm)

    assert_equal 'missing', lookup('pkg:deb/debian/tool-extra@1.0-1?arch=amd64&distro=debian-12').match_status
    assert_equal 'matched', lookup('pkg:deb/debian/tool-extra@1.1-1?arch=amd64&distro=debian-12').match_status
    assert_equal 'matched', lookup('pkg:deb/debian/tool@1.0-1?arch=amd64&distro=debian-12').match_status
    # versions stored before Binary was recorded per version can't be checked, so they still match
    assert_equal 'matched', lookup('pkg:deb/debian/tool-extra@0.9-1?arch=amd64&distro=debian-12').match_status
  end

  test 'does not match a binary name that is only a prefix of a listed binary' do
    assert_equal 'missing', lookup('pkg:deb/debian/libssl@3.0.22-1~deb12u2?distro=debian-12').match_status
  end

  test 'reports a vendor build of a package the distribution also ships as missing' do
    assert_equal 'missing', lookup('pkg:deb/debian/postgresql-15@15.3-1.pgdg120+1?arch=amd64&distro=debian-12').match_status
    assert_equal 'missing', lookup('pkg:deb/debian/postgresql-client-15@15.3-1.pgdg120+1?arch=amd64&distro=debian-12&upstream=postgresql-15').match_status
  end

  test 'reports a version the release did not publish as missing' do
    assert_equal 'missing', lookup('pkg:deb/debian/libssl3@3.0.11-1~deb12u1?arch=amd64&distro=debian-12&upstream=openssl').match_status
  end

  test 'only looks in the release named by the distro qualifier' do
    assert_equal 'missing', lookup('pkg:deb/debian/libssl3@3.0.22-1~deb12u2?arch=amd64&distro=debian-13&upstream=openssl').match_status
  end

  test 'leaves other package types alone' do
    registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    registry.packages.create!(name: 'rand', ecosystem: 'cargo').versions.create!(number: '0.8.5')

    assert_equal 'missing', lookup('pkg:cargo/rand@0.8.5+b1').match_status
  end
end
