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
      metadata: { "arch" => "amd64" }
    )
    @ecosystem = Ecosystem::Openbsd.new(@registry)
    @row = {
      "PathId" => 42,
      "FullPkgPath" => "www/nghttp2",
      "PKGNAME" => "nghttp2-1.68.1",
      "COMMENT" => "HTTP/2 C library",
      "HOMEPAGE" => "https://nghttp2.org/",
      "FULLPKGNAME" => "nghttp2-1.68.1",
      "PKGSTEM" => "nghttp2",
      "SUBPACKAGE" => nil,
      "MAINTAINER" => "OpenBSD ports <ports@openbsd.org>",
    }
    @package = Package.new(ecosystem: "openbsd", name: "www/nghttp2")
    @version = @package.versions.build(number: "1.68.1")
    @ecosystem.stubs(:synced_ports).returns([@row])
    @ecosystem.stubs(:load_index_basenames).returns(
      { "nghttp2-1.68.1.tgz" => { mtime: Time.utc(2026, 4, 25, 13, 27, 59) } }
    )
  end

  test "registry_url" do
    assert_equal "https://cvsweb.openbsd.org/cgi-bin/cvsweb/ports/www/nghttp2/", @ecosystem.registry_url(@package)
  end

  test "download_url with version uses FULLPKGNAME" do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal(
      "https://cdn.openbsd.org/pub/OpenBSD/7.9/packages/amd64/nghttp2-1.68.1.tgz",
      download_url
    )
  end

  test "install_command uses FULLPKGNAME when available" do
    assert_equal "pkg_add nghttp2-1.68.1", @ecosystem.install_command(@package)
  end

  test "purl" do
    purl = @ecosystem.purl(@package)
    assert_equal "pkg:openbsd/www/nghttp2?arch=amd64", purl
    assert Purl.parse(purl)
  end

  test "purl with version" do
    purl = @ecosystem.purl(@package, @version)
    assert_equal "pkg:openbsd/www/nghttp2@1.68.1?arch=amd64", purl
    assert Purl.parse(purl)
  end

  test "map_package_metadata" do
    meta = @ecosystem.map_package_metadata(@row)
    assert_equal "www/nghttp2", meta[:name]
    assert_equal "HTTP/2 C library", meta[:description]
    assert_equal "https://nghttp2.org/", meta[:homepage]
    assert_equal "www", meta[:namespace]
    assert_equal "nghttp2-1.68.1", meta[:metadata][:fullpkgname]
  end

  test "versions_metadata" do
    versions = @ecosystem.versions_metadata({ name: "www/nghttp2" })
    assert_equal 1, versions.size
    assert_equal "1.68.1", versions.first[:number]
    assert_equal Time.utc(2026, 4, 25, 13, 27, 59), versions.first[:published_at]
  end

  test "dependencies_metadata resolves only synced peers" do
    @ecosystem.stubs(:sqlite3_json_dependency_paths).returns(%w[inverted/missing www/nghttp3])
    other = @row.merge(
      "PathId" => 43,
      "FullPkgPath" => "www/nghttp3",
      "FULLPKGNAME" => "nghttp3-1.14.0",
      "PKGSTEM" => "nghttp3",
      "PKGNAME" => "nghttp3-1.14.0"
    )
    @ecosystem.stubs(:synced_ports).returns([@row, other])

    deps = @ecosystem.dependencies_metadata("www/nghttp2", nil, {})
    names = deps.map { |d| d[:package_name] }
    assert_includes names, "www/nghttp3"
    assert_not_includes names, "inverted/missing"
    assert deps.all? { |d| d[:ecosystem] == "openbsd" }
  end

  test "maintainers_metadata parses Maintainer field" do
    maintainers = @ecosystem.maintainers_metadata("www/nghttp2")
    assert_equal 1, maintainers.size
    assert_equal "ports@openbsd.org", maintainers.first[:uuid]
    assert_equal "OpenBSD ports", maintainers.first[:name]
  end
end
