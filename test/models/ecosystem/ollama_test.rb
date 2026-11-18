require "test_helper"

class OllamaTest < ActiveSupport::TestCase
  LATEST_DIGEST = "sha256:1b226e2802dbb772b5fc32a58f103ca1804ef7501331012de126ab22f67475ef"

  setup do
    @registry = Registry.new(default: true, name: "ollama.com", url: "https://ollama.com", ecosystem: "ollama")
    @ecosystem = Ecosystem::Ollama.new(@registry)
    @package = Package.new(ecosystem: "ollama", name: "all-minilm")
    @version = @package.versions.build(number: "latest", metadata: { "digest" => LATEST_DIGEST })
  end

  def stub_library
    stub_request(:get, "https://ollama.com/library").to_return(status: 200, body: file_fixture("ollama/library.html"))
  end

  def stub_model
    stub_library
    stub_request(:get, "https://ollama.com/library/all-minilm/tags")
      .to_return(status: 200, body: file_fixture("ollama/all-minilm-tags.html"))
    stub_request(:get, %r{\Ahttps://registry\.ollama\.ai/v2/library/all-minilm/manifests/})
      .to_return(status: 200, body: file_fixture("ollama/all-minilm-manifest.json"))
    stub_request(:get, "https://registry.ollama.ai/v2/library/all-minilm/blobs/sha256:548455b7265836afeea130cfc8919fa3311af2a55b9fec3cbd04e811bb600ee8")
      .to_return(status: 200, body: file_fixture("ollama/all-minilm-config.json"))
  end

  test "registry_url" do
    assert_equal "https://ollama.com/library/all-minilm", @ecosystem.registry_url(@package)
  end

  test "registry_url with version" do
    assert_equal "https://ollama.com/library/all-minilm:latest", @ecosystem.registry_url(@package, @version)
  end

  test "download_url is nil because a model is a set of layers" do
    assert_nil @ecosystem.download_url(@package, @version)
  end

  test "documentation_url" do
    assert_equal "https://ollama.com/library/all-minilm", @ecosystem.documentation_url(@package)
  end

  test "install_command" do
    assert_equal "ollama pull all-minilm", @ecosystem.install_command(@package)
  end

  test "install_command with version" do
    assert_equal "ollama pull all-minilm:latest", @ecosystem.install_command(@package, @version)
  end

  test "purl uses the oci type with the registry repository" do
    assert_equal "pkg:oci/all-minilm?repository_url=registry.ollama.ai/library/all-minilm", @ecosystem.purl(@package)
    assert Purl.parse(@ecosystem.purl(@package))
  end

  test "purl with version uses the manifest digest and names the tag" do
    purl = @ecosystem.purl(@package, @version)

    assert_equal "pkg:oci/all-minilm@sha256%3A1b226e2802dbb772b5fc32a58f103ca1804ef7501331012de126ab22f67475ef?repository_url=registry.ollama.ai/library/all-minilm&tag=latest", purl
    assert_equal LATEST_DIGEST, Purl.parse(purl).version
  end

  test "purl ignores the website url of a non-default registry" do
    @registry.default = false

    assert_equal "pkg:oci/all-minilm?repository_url=registry.ollama.ai/library/all-minilm", @ecosystem.purl(@package)
  end

  test "all_package_names" do
    stub_library

    assert_equal ["llama3.1", "nomic-embed-text", "all-minilm"], @ecosystem.all_package_names
  end

  test "all_package_names is empty when the library page fails" do
    stub_request(:get, "https://ollama.com/library").to_return(status: 500)

    assert_equal [], @ecosystem.all_package_names
  end

  test "recently_updated_package_names" do
    stub_request(:get, "https://ollama.com/library?sort=newest").to_return(status: 200, body: file_fixture("ollama/library.html"))

    assert_equal ["llama3.1", "nomic-embed-text", "all-minilm"], @ecosystem.recently_updated_package_names
  end

  test "package_metadata" do
    stub_model

    metadata = @ecosystem.package_metadata("all-minilm")

    assert_equal "all-minilm", metadata[:name]
    assert_equal "Embedding models on very large sentence level datasets.", metadata[:description]
    assert_equal ["embedding"], metadata[:keywords_array]
    assert_equal 3_900_000, metadata[:downloads]
    assert_equal "total", metadata[:downloads_period]
    assert_equal({
      "dist-tags": { "latest" => "latest" },
      updated_at: "May 6, 2024 11:38 PM UTC",
      model_format: "gguf",
      model_family: "bert",
      parameter_size: "23M",
      quantization: "F16"
    }, metadata[:metadata])
  end

  test "package_metadata is false for a missing model" do
    stub_request(:get, "https://ollama.com/library/nope/tags").to_return(status: 404)

    assert_equal false, @ecosystem.package_metadata("nope")
  end

  test "check_status is removed for a missing model" do
    stub_request(:get, "https://ollama.com/library/all-minilm/tags").to_return(status: 404)

    assert_equal "removed", @ecosystem.check_status(@package)
  end

  test "check_status leaves the status alone when the tags page errors" do
    stub_request(:get, "https://ollama.com/library/all-minilm/tags").to_return(status: 503)

    assert_equal false, @ecosystem.check_status(@package)
  end

  test "sync_package makes the latest tag the latest version" do
    stub_model
    registry = Registry.create!(default: true, name: "ollama.com", url: "https://ollama.com", ecosystem: "ollama")

    package = registry.sync_package("all-minilm")

    assert_equal "latest", package.latest_version_from(package.versions.to_a).number
  end

  test "parse_pulls" do
    assert_equal 523, @ecosystem.parse_pulls("523")
    assert_equal 950_000, @ecosystem.parse_pulls("950K")
    assert_equal 112_500_000, @ecosystem.parse_pulls("112.5M")
    assert_equal 1_200_000_000, @ecosystem.parse_pulls("1.2B")
    assert_nil @ecosystem.parse_pulls(nil)
  end

  test "sync_package stores each tag as a version with its manifest digest" do
    stub_model
    registry = Registry.create!(default: true, name: "ollama.com", url: "https://ollama.com", ecosystem: "ollama")

    package = registry.sync_package("all-minilm")

    assert_equal %w[22m 22m-l6-v2-fp16 33m 33m-l12-v2-fp16 l12 l12-v2 l6 l6-v2 latest v2], package.versions.pluck(:number).sort
    version = package.versions.find_by(number: "latest")
    assert_equal LATEST_DIGEST, version.metadata["digest"]
    assert_equal 45_960_589, version.metadata["size"]
    assert_includes version.metadata["media_types"], "application/vnd.ollama.image.model"
    assert_equal "pkg:oci/all-minilm@sha256%3A1b226e2802dbb772b5fc32a58f103ca1804ef7501331012de126ab22f67475ef?repository_url=registry.ollama.ai/library/all-minilm&tag=latest", registry.purl(package, version)
  end

  test "sync_package refetches the manifest of a tag that moved" do
    stub_model
    registry = Registry.create!(default: true, name: "ollama.com", url: "https://ollama.com", ecosystem: "ollama")
    package = registry.packages.create!(ecosystem: "ollama", name: "all-minilm")
    moved = package.versions.create!(number: "latest", metadata: { "digest" => "sha256:#{'0' * 64}" })
    unmoved = package.versions.create!(number: "l6", metadata: { "digest" => LATEST_DIGEST, "size" => 1 })

    registry.sync_package("all-minilm", force: true)

    assert_equal LATEST_DIGEST, moved.reload.metadata["digest"]
    assert_equal 1, unmoved.reload.metadata["size"]
    assert_requested :get, "https://registry.ollama.ai/v2/library/all-minilm/manifests/l6", times: 0
  end
end
