require "test_helper"

class ApiV1PurlsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: "crates.io", url: "https://crates.io", ecosystem: "cargo")
    @package = @registry.packages.create!(ecosystem: "cargo", name: "rand", licenses: "MIT")
    @old_version = @package.versions.create!(number: "0.7.0", integrity: "sha256-old")
    @latest_version = @package.versions.create!(number: "0.8.0", integrity: "sha256-latest", latest: true)
    @latest_version.dependencies.create!(ecosystem: "cargo", package_name: "serde", requirements: "^1.0", kind: "runtime")
  end

  test "looks up the version specified by a PURL" do
    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand@0.7.0" }

    assert_response :success
    assert_template "purls/lookup", file: "purls/lookup.json.jbuilder"

    response = Oj.load(@response.body)
    assert_equal "pkg:cargo/rand@0.7.0", response["purl"]
    assert_equal "matched", response["match_status"]
    assert_equal "rand", response.dig("version", "name")
    assert_equal "0.7.0", response.dig("version", "version")
    assert_equal "pkg:cargo/rand@0.7.0?repository_url=https://crates.io", response.dig("version", "purl")
    assert_equal "MIT", response.dig("version", "license_expression")
    assert_equal "sha256-old", response.dig("version", "identifiers", "integrity")
    assert_equal "sha256-old", response.dig("version", "artifacts", 0, "integrity")
  end

  test "looks up the latest version when the PURL has no version" do
    Package.any_instance.expects(:latest_version).never

    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand" }

    assert_response :success

    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "0.8.0", response.dig("version", "version")
    assert_equal "serde", response.dig("version", "dependencies", 0, "package_name")
  end

  test "falls back when a package has no persisted latest version" do
    package = @registry.packages.create!(ecosystem: "cargo", name: "fallback")
    package.versions.create!(number: "0.7.0")
    package.versions.create!(number: "0.8.0")

    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/fallback" }

    assert_response :success
    assert_equal "matched", Oj.load(@response.body)["match_status"]
    assert_equal "0.8.0", Oj.load(@response.body).dig("version", "version")
  end

  test "fallback prefers the npm latest dist-tag over the highest stable version" do
    registry = Registry.create!(name: "npmjs.org", url: "https://registry.npmjs.org", ecosystem: "npm")
    package = registry.packages.create!(ecosystem: "npm", name: "tagged", metadata: { "dist-tags" => { "latest" => "1.0.0" } })
    package.versions.create!(number: "1.0.0")
    package.versions.create!(number: "2.0.0")
    expected = package.reload.latest_version.number
    Package.any_instance.expects(:latest_version).never

    get lookup_api_v1_purls_path, params: { purl: "pkg:npm/tagged" }

    assert_response :success
    assert_equal "1.0.0", expected
    assert_equal expected, Oj.load(@response.body).dig("version", "version")
  end

  test "fallback skips archived opam releases" do
    registry = Registry.create!(name: "opam.ocaml.org", url: "https://opam.ocaml.org", ecosystem: "opam")
    package = registry.packages.create!(ecosystem: "opam", name: "lwt")
    package.versions.create!(number: "1.0.0", metadata: { "archived" => false })
    package.versions.create!(number: "2.0.0", metadata: { "archived" => true })
    expected = package.reload.latest_version.number
    Package.any_instance.expects(:latest_version).never

    get lookup_api_v1_purls_path, params: { purl: "pkg:opam/lwt" }

    assert_response :success
    assert_equal "1.0.0", expected
    assert_equal expected, Oj.load(@response.body).dig("version", "version")
  end

  test "resolves canonical PyPI names against stored distribution names" do
    registry = Registry.create!(name: "pypi.org", url: "https://pypi.org", ecosystem: "pypi")
    package = registry.packages.create!(ecosystem: "pypi", name: "zope.interface", metadata: { "normalized_name" => "zope-interface" })
    package.versions.create!(number: "6.0", latest: true)
    package.versions.create!(number: "5.5.2")

    get lookup_api_v1_purls_path, params: { purl: "pkg:pypi/zope-interface@5.5.2" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "zope.interface", response.dig("version", "name")
    assert_equal "5.5.2", response.dig("version", "version")

    post bulk_lookup_api_v1_purls_path, params: { purls: ["pkg:pypi/zope-interface", "pkg:pypi/zope_interface@5.5.2"] }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal ["matched", "matched"], response.pluck("match_status")
    assert_equal ["6.0", "5.5.2"], response.map { |result| result.dig("version", "version") }
  end

  test "resolves Swift PURLs case-insensitively against stored GitHub identities" do
    registry = Registry.create!(name: "swiftpackageindex.com", url: "https://swiftpackageindex.com", ecosystem: "swiftpm")
    package = registry.packages.create!(ecosystem: "swiftpm", name: "github.com/Apple/swift-nio", metadata: { "normalized_name" => "github.com/apple/swift-nio" })
    package.versions.create!(number: "2.65.0", latest: true)

    get lookup_api_v1_purls_path, params: { purl: "pkg:swift/github.com/apple/swift-nio@2.65.0" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "github.com/Apple/swift-nio", response.dig("version", "name")

    post bulk_lookup_api_v1_purls_path, params: { purls: ["pkg:swift/github.com/apple/swift-nio"] }

    assert_response :success
    assert_equal ["matched"], Oj.load(@response.body).pluck("match_status")
  end

  test "resolves cocoapods subspec PURLs to the root package version" do
    registry = Registry.create!(name: "cocoapods.org", url: "https://cocoapods.org", ecosystem: "cocoapods", default: true)
    package = registry.packages.create!(ecosystem: "cocoapods", name: "KSCrash")
    package.versions.create!(number: "1.17.6", latest: true)

    ["pkg:cocoapods/KSCrash%2FReporting%2FFilters@1.17.6#Base",
     "pkg:cocoapods/KSCrash/Reporting/Filters@1.17.6",
     "pkg:cocoapods/KSCrash@1.17.6#Reporting/Filters/Base"].each do |purl|
      get lookup_api_v1_purls_path, params: { purl: purl }

      assert_response :success, purl
      response = Oj.load(@response.body)
      assert_equal "matched", response["match_status"], purl
      assert_equal "KSCrash", response.dig("version", "name"), purl
      assert_equal "1.17.6", response.dig("version", "version"), purl
    end

    post bulk_lookup_api_v1_purls_path, params: { purls: ["pkg:cocoapods/KSCrash%2FReporting%2FFilters@1.17.6#Base"] }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal ["matched"], response.pluck("match_status")
    assert_equal ["KSCrash"], response.map { |result| result.dig("version", "name") }
  end

  test "returns missing for cocoapods subspec PURLs with an unknown root" do
    Registry.create!(name: "cocoapods.org", url: "https://cocoapods.org", ecosystem: "cocoapods", default: true)

    get lookup_api_v1_purls_path, params: { purl: "pkg:cocoapods/MissingPod%2FSubspec@1.0.0" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
    assert_nil response["version"]
  end

  test "includes only advisories affecting the matched version" do
    @package.update!(advisories: [
      {
        "uuid" => "GHSA-old",
        "identifiers" => ["GHSA-old", "CVE-2020-0001"],
        "url" => "https://github.com/advisories/GHSA-old",
        "title" => "Old rand issue",
        "severity" => "HIGH",
        "packages" => [
          {
            "ecosystem" => "cargo",
            "package_name" => "rand",
            "versions" => [{ "vulnerable_version_range" => ">= 0.7.0, < 0.8.0", "first_patched_version" => "0.8.0" }]
          }
        ]
      }
    ])
    affected = {
      "uuid" => "GHSA-old",
      "identifiers" => ["GHSA-old", "CVE-2020-0001"],
      "url" => "https://github.com/advisories/GHSA-old",
      "title" => "Old rand issue",
      "severity" => "HIGH",
      "affected" => true,
      "fixed" => false,
      "fixed_versions" => ["0.8.0"]
    }

    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand@0.7.0" }

    assert_response :success
    assert_equal [affected], Oj.load(@response.body).dig("version", "advisories")

    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand@0.8.0" }

    assert_response :success
    assert_equal [], Oj.load(@response.body).dig("version", "advisories")

    post bulk_lookup_api_v1_purls_path, params: { purls: ["pkg:cargo/rand@0.7.0", "pkg:cargo/rand@0.8.0", "pkg:cargo/rand"] }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal ["0.7.0", "0.8.0", "0.8.0"], response.map { |result| result.dig("version", "version") }
    assert_equal [[affected], [], []], response.map { |result| result.dig("version", "advisories") }
  end

  test "returns missing when the PURL does not match a version" do
    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand@9.9.9" }

    assert_response :success

    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
    assert_nil response["version"]
  end

  test "returns missing for an invalid PURL" do
    get lookup_api_v1_purls_path, params: { purl: "not-a-purl" }

    assert_response :success

    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
  end

  test "returns ambiguous when the PURL identifies versions in multiple registries" do
    alternate_registry = Registry.create!(name: "alternate crates", url: "https://alternate.example", ecosystem: "cargo")
    alternate_package = alternate_registry.packages.create!(ecosystem: "cargo", name: "rand")
    alternate_package.versions.create!(number: "0.8.0")

    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand@0.8.0" }

    assert_response :success

    response = Oj.load(@response.body)
    assert_equal "ambiguous", response["match_status"]
    assert_nil response["version"]
  end

  test "uses the repository_url qualifier to select a registry" do
    central = Registry.create!(name: "maven central", url: "https://repo1.maven.org/maven2", ecosystem: "maven")
    google = Registry.create!(name: "maven google", url: "https://maven.google.com/", ecosystem: "maven")
    central.packages.create!(ecosystem: "maven", name: "com.example:library").versions.create!(number: "1.0.0")
    google_package = google.packages.create!(ecosystem: "maven", name: "com.example:library")
    google_package.versions.create!(number: "1.0.0")

    get lookup_api_v1_purls_path, params: { purl: "pkg:maven/com.example/library@1.0.0?repository_url=https://maven.google.com" }

    assert_response :success

    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "com.example:library", response.dig("version", "name")
  end

  test "returns bulk results in the order of the input PURLs" do
    alternate_registry = Registry.create!(name: "alternate crates", url: "https://alternate.example", ecosystem: "cargo")
    alternate_package = alternate_registry.packages.create!(ecosystem: "cargo", name: "rand")
    alternate_package.versions.create!(number: "0.8.0")

    post bulk_lookup_api_v1_purls_path, params: {
      purls: ["pkg:cargo/rand@0.7.0", "pkg:cargo/missing@1.0.0", "pkg:cargo/rand@0.8.0"]
    }

    assert_response :success
    assert_template "purls/bulk_lookup", file: "purls/bulk_lookup.json.jbuilder"

    response = Oj.load(@response.body)
    assert_equal ["pkg:cargo/rand@0.7.0", "pkg:cargo/missing@1.0.0", "pkg:cargo/rand@0.8.0"], response.pluck("purl")
    assert_equal ["matched", "missing", "ambiguous"], response.pluck("match_status")
  end

  test "returns bad request when the PURL parameter is missing" do
    get lookup_api_v1_purls_path

    assert_response :bad_request
    assert_equal "Missing purl parameter", Oj.load(@response.body)["error"]
  end

  test "returns bad request when the PURLs parameter is missing" do
    post bulk_lookup_api_v1_purls_path

    assert_response :bad_request
    assert_equal "Missing purls parameter", Oj.load(@response.body)["error"]
  end

  test "returns bad request when more than 100 PURLs are requested" do
    post bulk_lookup_api_v1_purls_path, params: { purls: (1..101).map { |i| "pkg:cargo/package#{i}" } }

    assert_response :bad_request
    assert_equal "Maximum 100 PURLs allowed per request", Oj.load(@response.body)["error"]
  end
end
