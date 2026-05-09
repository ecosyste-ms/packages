# frozen_string_literal: true

require "test_helper"

class PkgsrcTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(
      default: true,
      name: "pkgsrc-test",
      url: "https://cdn.example.test/pkgs/All",
      ecosystem: "pkgsrc",
      github: "pkgsrc",
      metadata: { "pkg_summary_filename" => "pkg_summary.gz" }
    )

    @ecosystem = Ecosystem::Pkgsrc.new(@registry)
    @fixture = Rails.root.join("test/fixtures/files/pkgsrc/pkg_summary")
    @ecosystem.stubs(:pkg_summary_archive_path).returns(@fixture)
  end

  test "registry_url uses pkgsrc.se with PKGPATH" do
    pkg = Package.new(ecosystem: "pkgsrc", name: "games/hello-kitty")

    assert_equal "https://pkgsrc.se/games/hello-kitty", @ecosystem.registry_url(pkg)
  end

  test "install_command with and without version" do
    pkg = Package.new(ecosystem: "pkgsrc", name: "games/hello-kitty")
    ver = pkg.versions.build(number: "2.6")

    assert_equal "pkg_add hello-kitty", @ecosystem.install_command(pkg)
    assert_equal "pkg_add hello-kitty-2.6", @ecosystem.install_command(pkg, ver)
  end

  test "download_url builds All URL from FILE_NAME" do
    pkg = Package.new(ecosystem: "pkgsrc", name: "games/hello-kitty")
    ver = pkg.versions.build(number: "2.5")

    assert_equal "https://cdn.example.test/pkgs/All/hello-kitty-2.5.tgz",
                 @ecosystem.download_url(pkg, ver)
  end

  test "map_package_metadata" do
    raw = @ecosystem.fetch_package_metadata_uncached("games/hello-kitty")
    mapped = @ecosystem.map_package_metadata(raw)

    assert_equal "games/hello-kitty", mapped[:name]
    assert_equal "Newer kitty", mapped[:description]
    assert_equal "https://example.test/hello-kitty", mapped[:homepage]
    assert_equal "games", mapped[:namespace]
    assert_equal "hello-kitty", mapped.dig(:metadata, :pkg_slug)
    assert_equal "hello-kitty-2.6", mapped.dig(:metadata, :pkgname_latest)
  end

  test "versions_metadata lists each PKGNAME version once" do
    raw = @ecosystem.fetch_package_metadata_uncached("games/hello-kitty")

    nums = @ecosystem.versions_metadata(raw, []).map { |row| row[:number] }.sort

    assert_equal %w[2.5 2.6].sort, nums.sort
    assert_predicate(@ecosystem.versions_metadata(raw, []).first[:published_at], :present?)
  end

  test "dependencies_metadata parses DEPENDS comparisons" do
    deps = @ecosystem.dependencies_metadata("games/hello-kitty", "2.6", nil)

    z = deps.find { |d| d[:package_name] == "zlib" }

    assert_equal ">=1.2", z[:requirements]

    ruby = deps.find { |d| d[:package_name] == "ruby" }

    assert_equal ">=30", ruby[:requirements]
    assert deps.all? { |d| d[:ecosystem] == "pkgsrc" }
  end

  test "purl" do
    pkg = Package.new(
      ecosystem: "pkgsrc",
      name: "devel/minizip"
    )

    purl_str = @ecosystem.purl(pkg)

    assert_equal "pkg:pkgsrc/devel/minizip", purl_str
    assert_predicate Purl.parse(purl_str), :present?
  end

  test "hyphen PKGPATH keeps remainder in PURL namespace and name" do
    pkg = Package.new(ecosystem: "pkgsrc", name: "games/hello-kitty")

    assert_equal "pkg:pkgsrc/games/hello-kitty", @ecosystem.purl(pkg)
  end

  test "hyphen PKGPATH splits version suffix from PKGNAME" do
    rec = {

      "PKGPATH" => "games/hello-kitty",
      "PKGNAME" => "hello-kitty-2.6",
    }

    assert_equal "2.6", @ecosystem.send(:version_string_for, rec)
  end

  test "all_package_names includes indexed PKGPATH" do
    assert_includes @ecosystem.all_package_names, "games/hello-kitty"
    assert_includes @ecosystem.all_package_names, "devel/minizip"
  end

  test "check_status removed when missing" do
    g = Ecosystem::Pkgsrc.new(@registry)
    g.stubs(:pkg_summary_archive_path).returns(@fixture)
    pkg = Package.new(ecosystem: "pkgsrc", name: "zzz/missing-pack")

    assert_equal "removed", g.check_status(pkg)
  end
end
