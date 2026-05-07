# frozen_string_literal: true

require "test_helper"

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
    @fixture_root = Rails.root.join("test/fixtures/files/gentoo/md5-cache")
    @ecosystem.stubs(:md5_cache_root).returns(@fixture_root)

    f1 = @fixture_root.join("app-misc", "demo-1.0-r1")
    f2 = @fixture_root.join("app-misc", "demo-2.0")
    fb = @fixture_root.join("dev-libs", "baselayout-1.0")
    FileUtils.touch([fb], mtime: Time.zone.parse("2020-06-01").to_time)
    FileUtils.touch([f1], mtime: Time.zone.parse("2025-01-01").to_time)
    FileUtils.touch([f2], mtime: Time.zone.parse("2026-01-01").to_time)
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
  end

  test "install_command with and without version" do
    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")
    ver = pkg.versions.build(number: "2.0")

    assert_equal "emerge app-misc/demo", @ecosystem.install_command(pkg)
    assert_equal "emerge =app-misc/demo-2.0", @ecosystem.install_command(pkg, ver)
  end

  test "download_url uses first http URL from SRC_URI" do
    pkg = Package.new(ecosystem: "gentoo", name: "app-misc/demo")

    assert_equal(
      "https://downloads.example.com/demo-2.0.tar.xz",
      @ecosystem.download_url(pkg, pkg.versions.build(number: "2.0"))
    )
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
    assert_predicate versions.first[:integrity], :present?
  end

  test "dependencies_metadata splits runtime and build atoms" do
    deps = @ecosystem.dependencies_metadata("app-misc/demo", "1.0-r1", nil)

    run_names = deps.select { |d| d[:kind] == "runtime" }.map { |d| d[:package_name] }.sort
    build_names = deps.select { |d| d[:kind] == "build" }.map { |d| d[:package_name] }.sort

    assert_includes run_names, "dev-libs/baselayout"
    assert_includes run_names, "virtual/libc"
    assert_equal ["sys-devel/gcc"], build_names
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
  end

  test "check_status removed for unknown atom" do
    pkg = Package.new(ecosystem: "gentoo", name: "acct-group/unknown-xyz")
    g = Ecosystem::Gentoo.new(@registry)

    g.stubs(:md5_cache_root).returns(@fixture_root)

    assert_equal "removed", g.check_status(pkg)
  end

  test "recently_updated_package_names prefers newer cache mtimes" do
    names = @ecosystem.recently_updated_package_names

    assert_includes names, "app-misc/demo"
    assert names.index("app-misc/demo") < names.index("dev-libs/baselayout")
  end
end
