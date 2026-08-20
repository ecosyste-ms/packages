require "test_helper"

class HuggingfaceTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: "huggingface.co", url: "https://huggingface.co", ecosystem: "huggingface")
    @ecosystem = Ecosystem::Huggingface.new(@registry)
    @package = Package.new(ecosystem: "huggingface", name: "openai-community/gpt2")
    @version = @package.versions.build(number: "0123456789abcdef0123456789abcdef01234567")
  end

  test "registry_url" do
    assert_equal "https://huggingface.co/openai-community/gpt2", @ecosystem.registry_url(@package)
  end

  test "registry_url with version" do
    assert_equal "https://huggingface.co/openai-community/gpt2/tree/0123456789abcdef0123456789abcdef01234567", @ecosystem.registry_url(@package, @version)
  end

  test "download_url is nil because models have no universal archive" do
    assert_nil @ecosystem.download_url(@package, @version)
  end

  test "documentation_url" do
    assert_equal "https://huggingface.co/openai-community/gpt2", @ecosystem.documentation_url(@package)
  end

  test "documentation_url with version" do
    assert_equal "https://huggingface.co/openai-community/gpt2/tree/0123456789abcdef0123456789abcdef01234567", @ecosystem.documentation_url(@package, @version)
  end

  test "install_command" do
    assert_equal "hf download openai-community/gpt2", @ecosystem.install_command(@package)
  end

  test "install_command with version" do
    assert_equal "hf download openai-community/gpt2 --revision 0123456789abcdef0123456789abcdef01234567", @ecosystem.install_command(@package, @version)
  end

  test "purl" do
    assert_equal "pkg:huggingface/openai-community/gpt2", @ecosystem.purl(@package)
    assert Purl.parse(@ecosystem.purl(@package))
  end

  test "purl with version" do
    assert_equal "pkg:huggingface/openai-community/gpt2@0123456789abcdef0123456789abcdef01234567", @ecosystem.purl(@package, @version)
    assert Purl.parse(@ecosystem.purl(@package, @version))
  end

  test "all_package_names follows cursor pagination" do
    stub_request(:get, "https://huggingface.co/api/models?limit=1000")
      .to_return(
        status: 200,
        headers: { "Link" => "<https://huggingface.co/api/models?limit=1000&cursor=next-page>; rel=\"next\"" },
        body: file_fixture("huggingface/models-page-1.json")
      )
    stub_request(:get, "https://huggingface.co/api/models?limit=1000&cursor=next-page")
      .to_return(status: 200, body: file_fixture("huggingface/models-page-2.json"))

    assert_equal ["openai-community/gpt2", "stabilityai/sdxl-turbo", "sentence-transformers/all-MiniLM-L6-v2"], @ecosystem.all_package_names
  end

  test "sync_missing_packages_async enqueues missing models and saves the next cursor" do
    registry = Registry.create!(default: true, name: "Hugging Face discovery", url: "https://huggingface-discovery.example", ecosystem: "huggingface")
    registry.packages.create!(name: "openai-community/gpt2", ecosystem: "huggingface")
    ecosystem = Ecosystem::Huggingface.new(registry)
    stub_request(:get, "https://huggingface.co/api/models?limit=1000")
      .to_return(
        status: 200,
        headers: { "Link" => "<https://huggingface.co/api/models?limit=1000&cursor=next-page>; rel=\"next\"" },
        body: file_fixture("huggingface/models-page-1.json")
      )
    SyncPackageWorker.expects(:perform_bulk).with([
      [registry.id, "stabilityai/sdxl-turbo"]
    ])

    assert_equal 1, ecosystem.sync_missing_packages_async
    assert_equal "https://huggingface.co/api/models?limit=1000&cursor=next-page", registry.reload.metadata[Ecosystem::Huggingface::SYNC_MISSING_CURSOR_KEY]
  end

  test "sync_missing_packages_async clears its cursor at the end of the catalogue" do
    registry = Registry.create!(
      default: true,
      name: "Hugging Face discovery end",
      url: "https://huggingface-discovery-end.example",
      ecosystem: "huggingface",
      metadata: { Ecosystem::Huggingface::SYNC_MISSING_CURSOR_KEY => "https://huggingface.co/api/models?limit=1000&cursor=last-page" }
    )
    ecosystem = Ecosystem::Huggingface.new(registry)
    stub_request(:get, "https://huggingface.co/api/models?limit=1000&cursor=last-page")
      .to_return(status: 200, body: file_fixture("huggingface/models-page-2.json"))
    SyncPackageWorker.expects(:perform_bulk).with([
      [registry.id, "sentence-transformers/all-MiniLM-L6-v2"]
    ])

    assert_equal 1, ecosystem.sync_missing_packages_async
    assert_nil registry.reload.metadata[Ecosystem::Huggingface::SYNC_MISSING_CURSOR_KEY]
  end

  test "sync_missing_packages_async keeps its cursor when the API fails" do
    registry = Registry.create!(
      default: true,
      name: "Hugging Face discovery failure",
      url: "https://huggingface-discovery-failure.example",
      ecosystem: "huggingface",
      metadata: { Ecosystem::Huggingface::SYNC_MISSING_CURSOR_KEY => "https://huggingface.co/api/models?limit=1000&cursor=retry" }
    )
    ecosystem = Ecosystem::Huggingface.new(registry)
    stub_request(:get, "https://huggingface.co/api/models?limit=1000&cursor=retry").to_return(status: 503)

    assert_equal 0, ecosystem.sync_missing_packages_async
    assert_equal "https://huggingface.co/api/models?limit=1000&cursor=retry", registry.reload.metadata[Ecosystem::Huggingface::SYNC_MISSING_CURSOR_KEY]
  end

  test "recently_updated_package_names" do
    stub_request(:get, "https://huggingface.co/api/models?limit=100&sort=lastModified&direction=-1")
      .to_return(status: 200, body: file_fixture("huggingface/models-page-1.json"))

    assert_equal ["openai-community/gpt2", "stabilityai/sdxl-turbo"], @ecosystem.recently_updated_package_names
  end

  test "package_metadata" do
    stub_model_request

    metadata = @ecosystem.package_metadata(@package.name)

    assert_equal "openai-community/gpt2", metadata[:name]
    assert_equal "openai-community", metadata[:namespace]
    assert_equal "https://huggingface.co/openai-community/gpt2", metadata[:homepage]
    assert_nil metadata[:repository_url]
    assert_nil metadata[:description]
    assert_equal "mit", metadata[:licenses]
    assert_equal ["transformers", "pytorch", "license:mit", "text-generation"], metadata[:keywords_array]
    assert_equal 123456, metadata[:downloads]
    assert_equal "last-month", metadata[:downloads_period]
    assert_equal 420, metadata[:metadata][:likes]
    assert_equal false, metadata[:metadata][:gated]
  end

  test "versions_metadata uses the model revision without treating it as an integrity hash" do
    stub_model_request

    metadata = @ecosystem.package_metadata(@package.name)
    versions = @ecosystem.versions_metadata(metadata)

    assert_equal [{
      number: "0123456789abcdef0123456789abcdef01234567",
      published_at: "2026-08-19T12:34:56.000Z",
      metadata: {
        revision: "0123456789abcdef0123456789abcdef01234567",
        created_at: "2022-11-23T17:29:44.000Z",
        last_modified: "2026-08-19T12:34:56.000Z"
      }
    }], versions
  end

  test "check_status returns removed for a missing model" do
    stub_request(:get, "https://huggingface.co/api/models/openai-community/gpt2").to_return(status: 404)

    assert_equal "removed", @ecosystem.check_status(@package)
  end

  test "check_status does not mark a model removed when the API errors" do
    stub_request(:get, "https://huggingface.co/api/models/openai-community/gpt2").to_return(status: 503)

    assert_nil @ecosystem.check_status(@package)
  end

  private

  def stub_model_request
    stub_request(:get, "https://huggingface.co/api/models/openai-community/gpt2")
      .to_return(status: 200, body: file_fixture("huggingface/openai-community-gpt2.json"))
  end
end
