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

  test "uses the distro qualifier to select an Alpine version from the right registry" do
    create_alpine_packages

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "curl", response.dig("version", "name")
    assert_equal "8.5.0-r0", response.dig("version", "version")
    assert_equal "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19", response.dig("version", "purl")
    assert_equal "https://dl-cdn.alpinelinux.org/alpine/v3.19/main/x86_64/curl-8.5.0-r0.apk", response.dig("version", "artifacts", 0, "download_url")
  end

  test "resolves a Syft-style Alpine point-release distro to its release registry" do
    create_alpine_packages

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19.1" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19", response.dig("version", "purl")
    assert_equal "https://dl-cdn.alpinelinux.org/alpine/v3.19/main/x86_64/curl-8.5.0-r0.apk", response.dig("version", "artifacts", 0, "download_url")
  end

  test "keeps a Syft-style distro scoped when the requested version is missing" do
    packages = create_alpine_packages
    packages.last.versions.create!(number: "8.6.0-r0")

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.6.0-r0?arch=x86_64&distro=alpine-3.19.1" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
    assert_nil response["version"]
  end

  test "returns ambiguous for the same Alpine version in multiple registries without qualifiers" do
    create_alpine_packages

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "ambiguous", response["match_status"]
    assert_nil response["version"]
  end

  test "returns missing for an unknown or differently cased distro qualifier" do
    create_alpine_packages

    ["alpine-3.18", "Alpine-3.19", "Alpine-3.19.1", "alpine-3.190.1"].each do |distro|
      get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=#{distro}" }

      assert_response :success
      response = Oj.load(@response.body)
      assert_equal "missing", response["match_status"], distro
      assert_nil response["version"]
    end
  end

  test "does not fall back to another distro when the requested version is missing" do
    packages = create_alpine_packages
    packages.last.versions.create!(number: "8.6.0-r0")

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.6.0-r0?arch=x86_64&distro=alpine-3.19" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
    assert_nil response["version"]
  end

  test "requires repository_url and distro to match the same registry" do
    packages = create_alpine_packages

    packages.each_with_index do |package, index|
      repository_url = "#{package.registry.url.upcase}/"
      purl = "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19&repository_url=#{repository_url}"
      get lookup_api_v1_purls_path, params: { purl: purl }

      assert_response :success
      response = Oj.load(@response.body)
      if index.zero?
        assert_equal "matched", response["match_status"]
        assert_equal "https://dl-cdn.alpinelinux.org/alpine/v3.19/main/x86_64/curl-8.5.0-r0.apk", response.dig("version", "artifacts", 0, "download_url")
      else
        assert_equal "missing", response["match_status"]
        assert_nil response["version"]
      end
    end
  end

  test "ignores registries with missing or blank versions when matching distro" do
    create_alpine_packages
    [nil, ""].each_with_index do |version, index|
      Registry.create!(name: "Alpine unknown #{index}", url: "https://alpine.example/unknown-#{index}", ecosystem: "alpine", version: version)
    end

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-3.19", response.dig("version", "purl")
  end

  test "returns missing when a distro qualifier is unsupported by the ecosystem" do
    @registry.update!(version: "1")

    get lookup_api_v1_purls_path, params: { purl: "pkg:cargo/rand@0.8.0?distro=x" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
    assert_nil response["version"]
  end

  test "returns missing when computing the distro qualifier is not implemented" do
    create_alpine_packages
    Ecosystem::Alpine.any_instance.stubs(:distro_qualifier).raises(NotImplementedError)

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/alpine/curl@8.5.0-r0?distro=alpine-3.19" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "missing", response["match_status"]
    assert_nil response["version"]
  end

  test "returns distro-qualified bulk results in input order" do
    create_alpine_packages
    purls = ["3.19", "3.21", "3.18"].map do |branch|
      "pkg:apk/alpine/curl@8.5.0-r0?arch=x86_64&distro=alpine-#{branch}"
    end

    post bulk_lookup_api_v1_purls_path, params: { purls: purls }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal purls, response.pluck("purl")
    assert_equal ["matched", "matched", "missing"], response.pluck("match_status")
    assert_equal purls.first(2), response.first(2).map { |result| result.dig("version", "purl") }
    assert_nil response.last["version"]
  end

  test "routes deb PURL namespaces to Debian and Ubuntu registries" do
    registries = [
      Registry.create!(name: "Debian 12", url: "https://packages.debian.org/bookworm", ecosystem: "debian", version: "12", default: true),
      Registry.create!(name: "Ubuntu 24.04", url: "https://packages.ubuntu.com/noble", ecosystem: "ubuntu", version: "24.04", default: true)
    ]
    registries.each do |registry|
      registry.packages.create!(ecosystem: registry.ecosystem, name: "curl").versions.create!(number: "8.5.0-1")
    end

    registries.each do |registry|
      distro = "#{registry.ecosystem}-#{registry.version}"
      purl = "pkg:deb/#{registry.ecosystem}/curl@8.5.0-1?arch=source&distro=#{distro}"
      get lookup_api_v1_purls_path, params: { purl: purl }

      assert_response :success
      response = Oj.load(@response.body)
      assert_equal "matched", response["match_status"], distro
      assert_equal purl, response.dig("version", "purl")
    end
  end

  test "resolves a generated postmarketOS PURL to its registry" do
    create_alpine_packages
    registry = Registry.create!(name: "postmarketOS v24.06", url: "https://pkgs.postmarketos.org/packages?branch=v24.06", ecosystem: "postmarketos", version: "v24.06")
    package = registry.packages.create!(ecosystem: "postmarketos", name: "curl", metadata: { "architecture" => "x86_64", "repository" => "main" })
    version = package.versions.create!(number: "8.5.0-r0")
    purl = version.purl
    assert_equal "pkg:apk/postmarketos/curl@8.5.0-r0?arch=x86_64&distro=postmarketos-24.06", purl

    get lookup_api_v1_purls_path, params: { purl: purl }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal purl, response.dig("version", "purl")
    assert_equal "https://mirror.postmarketos.org/postmarketos/v24.06/x86_64/curl-8.5.0-r0.apk", response.dig("version", "artifacts", 0, "download_url")
  end

  test "resolves an Adelie apk PURL without a distro qualifier" do
    registry = Registry.create!(name: "Adelie", url: "https://pkg.adelielinux.org/current", ecosystem: "adelie", default: true)
    package = registry.packages.create!(ecosystem: "adelie", name: "abuild", metadata: { "architecture" => "x86_64", "repository" => "system" })
    version = package.versions.create!(number: "3.5-r0")
    purl = version.purl
    assert_equal "pkg:apk/adelie/abuild@3.5-r0?arch=x86_64", purl

    get lookup_api_v1_purls_path, params: { purl: "pkg:apk/adelie/abuild@3.5-r0?arch=x86_64" }

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal "matched", response["match_status"]
    assert_equal "abuild", response.dig("version", "name")
    assert_equal "https://distfiles.adelielinux.org/adelie/current/system/x86_64/abuild-3.5-r0.apk", response.dig("version", "artifacts", 0, "download_url")
  end

  test "does not route unknown apk or deb namespaces to another ecosystem" do
    create_alpine_packages
    registry = Registry.create!(name: "Debian 12", url: "https://packages.debian.org/bookworm", ecosystem: "debian", version: "12", default: true)
    registry.packages.create!(ecosystem: "debian", name: "curl").versions.create!(number: "8.5.0-r0")

    ["pkg:apk/debian/curl@8.5.0-r0?distro=debian-12", "pkg:deb/alpine/curl@8.5.0-r0?distro=alpine-3.19"].each do |purl|
      get lookup_api_v1_purls_path, params: { purl: purl }

      assert_response :success
      response = Oj.load(@response.body)
      assert_equal "missing", response["match_status"], purl
      assert_nil response["version"]
    end
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

  private

  def create_alpine_packages
    ["3.19", "3.21"].map do |branch|
      registry = Registry.create!(name: "Alpine v#{branch}", url: "https://pkgs.alpinelinux.org/packages?branch=v#{branch}", ecosystem: "alpine", version: "v#{branch}")
      package = registry.packages.create!(ecosystem: "alpine", name: "curl", metadata: { "architecture" => "x86_64", "repository" => "main" })
      package.versions.create!(number: "8.5.0-r0")
      package
    end
  end
end
