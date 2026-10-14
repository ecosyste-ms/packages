# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class GentooTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(
      default: true,
      name: "gentoo-portage",
      url: "https://packages.gentoo.org/",
      ecosystem: "gentoo",
      github: "gentoo",
      metadata: { "snapshot_url" => "https://distfiles.gentoo.org/snapshots/portage-latest.tar.xz" }
    )
    @ecosystem = Ecosystem::Gentoo.new(@registry)
    @fixture_tmpdir = Dir.mktmpdir("gentoo-md5-cache-test")
    FileUtils.cp_r(Rails.root.join("test/fixtures/files/gentoo/md5-cache"), @fixture_tmpdir)

    @fixture_root = Pathname.new(File.join(@fixture_tmpdir, "md5-cache"))
    @ecosystem.stubs(:md5_cache_root).returns(@fixture_root)
    @ecosystem.stubs(:refresh_md5_cache).returns(@fixture_root)

    f1 = @fixture_root.join("app-misc", "demo-1.0-r1")
    f2 = @fixture_root.join("app-misc", "demo-2.0")
    fb = @fixture_root.join("dev-libs", "baselayout-1.0")
    ff = @fixture_root.join("media-fonts", "font-adobe-100dpi-1.0.4")
    FileUtils.touch([fb], mtime: Time.zone.parse("2020-06-01").to_time)
    FileUtils.touch([ff], mtime: Time.zone.parse("2024-01-01").to_time)
    FileUtils.touch([f1], mtime: Time.zone.parse("2025-01-01").to_time)
    FileUtils.touch([f2], mtime: Time.zone.parse("2026-01-01").to_time)
  end

  teardown do
    FileUtils.rm_rf(@fixture_tmpdir) if @fixture_tmpdir.present?
  end

  test "registry_url points at packages.gentoo.org" do
    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")

    assert_equal(
      "https://packages.gentoo.org/packages/app-misc/demo",
      @ecosystem.registry_url(pkg)
    )
  end

  test "all_package_names derives category/pn atoms" do
    names = @ecosystem.all_package_names.sort

    assert_includes names, "app-misc/demo"
    assert_includes names, "dev-libs/baselayout"
    assert_includes names, "media-fonts/font-adobe-100dpi"
  end

  test "install_command with and without version" do
    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")

    assert_equal "emerge app-misc/demo", @ecosystem.install_command(pkg)
    assert_equal "emerge =app-misc/demo-2.0", @ecosystem.install_command(pkg, "2.0")
  end

  test "Version#install_command delegates correctly" do
    pkg = Package.new(registry: @registry, ecosystem: "gentoo", name: "app-misc/demo")
    ver = Version.new(package: pkg, number: "2.0")

    assert_equal "emerge =app-misc/demo-2.0", ver.install_command
  end

  test "download_url reads from version metadata without touching the snapshot" do
    e = Ecosystem::Gentoo.new(@registry)
    e.expects(:md5_cache_root).never
    e.expects(:refresh_md5_cache).never

    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")
    ver = pkg.versions.build(
      number: "2.0",
      metadata: { "download_url" => "https://downloads.example.com/demo-2.0.tar.xz" }
    )

    assert_equal "https://downloads.example.com/demo-2.0.tar.xz", e.download_url(pkg, ver)
    assert_nil e.download_url(pkg, pkg.versions.build(number: "1.0", metadata: {}))
    assert_nil e.download_url(pkg, nil)
  end

  test "map_package_metadata" do
    raw = @ecosystem.fetch_package_metadata_uncached("app-misc/demo")
    mapped = @ecosystem.map_package_metadata(raw)

    assert_equal "app-misc/demo", mapped[:name]
    assert_equal "Demo two", mapped[:description]
    assert_equal "https://example.com/demo", mapped[:homepage]
    assert_equal "MIT", mapped[:licenses]
    assert_equal "app-misc", mapped[:namespace]
    assert_equal "0", mapped.dig(:metadata, :slot)
  end

  test "versions_metadata returns one row per ebuild in md5-cache" do
    raw = @ecosystem.fetch_package_metadata_uncached("app-misc/demo")
    mapped = @ecosystem.map_package_metadata(raw)
    versions = @ecosystem.versions_metadata(mapped, [])

    nums = versions.map { |v| v[:number] }.sort

    assert_equal ["1.0-r1", "2.0"], nums
    assert versions.none? { |v| v.key?(:integrity) }
    assert_equal(
      ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
      versions.map { |v| v.dig(:metadata, :ebuild_md5) }.sort
    )

    v2 = versions.find { |v| v[:number] == "2.0" }
    assert_equal "https://downloads.example.com/demo-2.0.tar.xz", v2.dig(:metadata, :download_url)
  end

  test "dependencies_metadata splits runtime and build atoms and skips blockers" do
    deps = @ecosystem.dependencies_metadata("app-misc/demo", "1.0-r1", nil)

    run_names = deps.select { |d| d[:kind] == "runtime" }.map { |d| d[:package_name] }.sort
    build_names = deps.select { |d| d[:kind] == "build" }.map { |d| d[:package_name] }.sort

    assert_includes run_names, "dev-libs/baselayout"
    assert_includes run_names, "virtual/libc"
    assert_not_includes run_names, "sys-libs/zlib"
    assert_not_includes run_names, "dev-libs/blocked"
    assert_equal ["sys-devel/gcc", "sys-libs/zlib"], build_names
    assert(deps.all? { |d| d[:ecosystem] == "gentoo" })
  end

  test "purl" do
    pkg = Package.new(
      ecosystem: "gentoo",
      name: "app-misc/demo",
      metadata: { "slot" => "0" }
    )

    purl_str = @ecosystem.purl(pkg)

    assert_match %r{\Apkg:gentoo/app-misc/demo\z}, purl_str
    assert Purl.parse(purl_str)
  end

  test "purl with version" do
    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")
    purl_str = @ecosystem.purl(pkg, pkg.versions.build(number: "2.0"))

    assert_equal "pkg:gentoo/app-misc/demo@2.0", purl_str
    assert Purl.parse(purl_str)
  end

  test "hyphenated PN splits with valid_pv" do
    assert_equal %w[foo-bar 1.0], @ecosystem.send(:split_package_version, "foo-bar-1.0")
    assert_equal %w[font-adobe-100dpi 1.0.4], @ecosystem.send(:split_package_version, "font-adobe-100dpi-1.0.4")
  end

  test "check_status removed for unknown atom" do
    pkg = Package.new(ecosystem: "gentoo", name: "acct-group/unknown-xyz")
    g = Ecosystem::Gentoo.new(@registry)

    g.stubs(:md5_cache_root).returns(@fixture_root)

    assert_equal "removed", g.check_status(pkg)
  end

  test "check_status is nil when md5 cache is not on disk" do
    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")
    g = Ecosystem::Gentoo.new(@registry)

    g.stubs(:md5_cache_root).returns(nil)

    assert_nil g.check_status(pkg)
  end

  test "md5_cache_root is read-only and does not download" do
    g = Ecosystem::Gentoo.new(@registry)
    g.expects(:download_and_cache).never
    g.stubs(:md5_cache_dest).returns(Pathname.new("/nonexistent/gentoo-md5-cache"))

    assert_nil g.md5_cache_root
  end

  test "recently_updated_package_names prefers newer cache mtimes" do
    names = @ecosystem.recently_updated_package_names

    assert_includes names, "app-misc/demo"
    assert names.index("app-misc/demo") < names.index("dev-libs/baselayout")
  end
end
