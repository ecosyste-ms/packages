# frozen_string_literal: true

require "test_helper"

class OpenbsdTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(
      default: true,
      name: "openbsd-7.9-amd64",
      url: "https://cdn.openbsd.org/pub/OpenBSD/7.9/packages/amd64",
      ecosystem: "openbsd",
      version: "7.9",
      metadata: { "arch" => "amd64", "sqlports_tgz" => "sqlports-7.54.tgz" }
    )
    @ecosystem = Ecosystem::Openbsd.new(@registry)
    @index_fixture = Rails.root.join("test/fixtures/files/openbsd/index.txt")
    @sqlports_fixture = Rails.root.join("test/fixtures/files/openbsd/sqlports-7.54.tgz")

    def @ecosystem.download_and_cache(url, *_args, **_kwargs)
      fixtures = Rails.root.join("test/fixtures/files/openbsd")
      return fixtures.join("index.txt") if url.end_with?("/index.txt")
      return fixtures.join("sqlports-7.54.tgz") if url.end_with?("/sqlports-7.54.tgz")

      nil
    end

    @package = Package.new(ecosystem: "openbsd", name: "devel/git")
    @version = @package.versions.build(number: "2.49.0")
    @row = @ecosystem.fetch_package_metadata_uncached("devel/git")
  end

  test "registry_url" do
    assert_equal "https://cvsweb.openbsd.org/cgi-bin/cvsweb/ports/devel/git/", @ecosystem.registry_url(@package)
  end

  test "download_url with version uses FULLPKGNAME" do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal(
      "https://cdn.openbsd.org/pub/OpenBSD/7.9/packages/amd64/git-2.49.0.tgz",
      download_url
    )
  end

  test "install_command uses FULLPKGNAME when available" do
    assert_equal "pkg_add git-2.49.0", @ecosystem.install_command(@package)
  end

  test "purl" do
    purl = @ecosystem.purl(@package)
    assert_equal "pkg:openbsd/devel/git?arch=amd64", purl
    assert Purl.parse(purl)
  end

  test "purl with version" do
    purl = @ecosystem.purl(@package, @version)
    assert_equal "pkg:openbsd/devel/git@2.49.0?arch=amd64", purl
    assert Purl.parse(purl)
  end

  test "map_package_metadata" do
    meta = @ecosystem.map_package_metadata(@row)
    assert_equal "devel/git", meta[:name]
    assert_equal "distributed version control system", meta[:description]
    assert_equal "https://git-scm.com/", meta[:homepage]
    assert_equal "devel", meta[:namespace]
    assert_equal "git-2.49.0", meta[:metadata][:fullpkgname]
  end

  test "versions_metadata" do
    versions = @ecosystem.versions_metadata({ name: "devel/git" })
    assert_equal 1, versions.size
    assert_equal "2.49.0", versions.first[:number]
    assert_equal Time.utc(2026, 4, 25, 13, 27, 59), versions.first[:published_at]
  end

  test "versions_metadata splits version at the last hyphen before a digit" do
    versions = @ecosystem.versions_metadata({ name: "lang/php/8.2" })
    assert_equal ["8.2.30p2"], versions.map { |v| v[:number] }
  end

  test "dependencies_metadata maps sqlports dependency types" do
    deps = @ecosystem.dependencies_metadata("devel/git", nil, {})
    runtime_names = deps.select { |d| d[:kind] == "runtime" }.map { |d| d[:package_name] }
    build_names = deps.select { |d| d[:kind] == "build" }.map { |d| d[:package_name] }

    assert_includes runtime_names, "net/curl"
    assert_includes runtime_names, "devel/gettext,-tools"
    assert_includes build_names, "devel/gettext,-tools"
    assert_not_includes deps.map { |d| d[:package_name] }, "archivers/unzip"
    assert deps.all? { |d| d[:ecosystem] == "openbsd" }
    assert deps.all? { |d| d[:requirements] == "*" }
  end

  test "dependencies_metadata returns empty for ports without deps" do
    assert_equal [], @ecosystem.dependencies_metadata("net/curl", nil, {})
  end

  test "maintainers_metadata parses Maintainer field" do
    maintainers = @ecosystem.maintainers_metadata("devel/git")
    assert_equal 2, maintainers.size
    assert_equal ["semarie@online.fr", "robert@openbsd.org"], maintainers.map { |m| m[:uuid] }
    assert_equal ["Sebastien Marie", "Robert Nagy"], maintainers.map { |m| m[:name] }
    assert_equal ["semarie@online.fr", "robert@openbsd.org"], maintainers.map { |m| m[:email] }
    assert maintainers.none? { |m| m.key?(:url) }
  end

  test "maintainers_metadata skips entries without email" do
    assert_equal [], @ecosystem.maintainers_metadata("devel/gettext,-tools")
  end

  test "all_package_names exercises index parsing tar extraction and sql" do
    assert_includes @ecosystem.all_package_names, "devel/git"
    assert_includes @ecosystem.all_package_names, "net/curl"
    assert_not_includes @ecosystem.all_package_names, "archivers/unzip"
  end

  test "discover_sqlports_tgz_filename sorts by version" do
    @ecosystem.stubs(:get_raw).returns('<a href="sqlports-7.9.tgz">old</a><a href="sqlports-7.10.tgz">new</a>')

    assert_equal "sqlports-7.10.tgz", @ecosystem.discover_sqlports_tgz_filename
  end

  test "load_synced_ports handles binary-encoded discovered sqlports filename" do
    registry = Registry.new(
      name: "openbsd-7.9-amd64",
      url: "https://cdn.openbsd.org/pub/OpenBSD/7.9/packages/amd64",
      ecosystem: "openbsd",
      metadata: { "arch" => "amd64" }
    )
    ecosystem = Ecosystem::Openbsd.new(registry)

    def ecosystem.download_and_cache(url, *_args, **_kwargs)
      fixtures = Rails.root.join("test/fixtures/files/openbsd")
      return fixtures.join("index.txt") if url.end_with?("/index.txt")
      return fixtures.join("sqlports-7.54.tgz") if url.end_with?("/sqlports-7.54.tgz")

      nil
    end

    body = (+'<a href="sqlports-7.54.tgz">x</a>').force_encoding(Encoding::ASCII_8BIT)
    ecosystem.stubs(:get_raw).returns(body)

    assert_includes ecosystem.all_package_names, "devel/git"
  end
end
