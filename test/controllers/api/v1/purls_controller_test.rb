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
    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand" }

    assert_response :success

    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "0.8.0", response.dig("version", "version")
    assert_equal "serde", response.dig("version", "dependencies", 0, "package_name")
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
