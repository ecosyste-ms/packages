require 'test_helper'

class ApiV1ArtifactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create!(ecosystem: 'cargo', name: 'rand')
    @version = @package.versions.create!(number: '1.0.0', registry: @registry)
    @artifact = @version.artifacts.create!(
      identifier: 'rand-1.0.0.crate',
      filename: 'rand-1.0.0.crate',
      kind: 'crate',
      download_url: 'https://static.crates.io/crates/rand/rand-1.0.0.crate',
      size: 123,
      published_at: 1.day.ago,
      integrity: "sha256-#{'a' * 64}",
      metadata: { 'source' => 'registry' }
    )
  end

  test 'lists artifacts for a version with pagination' do
    @version.artifacts.create!(identifier: 'rand-1.0.0.asc')
    @version.artifacts.create!(identifier: 'rand-1.0.0.sig')

    get api_v1_registry_package_version_artifacts_path(
      registry_id: @registry.name,
      package_id: @package.name,
      version_id: @version.number,
      per_page: 2
    )

    assert_response :success
    assert_template 'artifacts/index', file: 'artifacts/index.json.jbuilder'
    assert_equal 2, Oj.load(@response.body).length
  end

  test 'gets an artifact' do
    get api_v1_artifact_path(@artifact)

    assert_response :success
    assert_template 'artifacts/show', file: 'artifacts/show.json.jbuilder'
    response = Oj.load(@response.body)
    assert_equal @artifact.identifier, response['identifier']
    assert_equal @artifact.metadata, response['metadata']
    assert_equal api_v1_registry_package_version_url(@registry, @package, @version), response['version_url']
  end

  test 'lookup prefers an exact integrity value' do
    digest = 'b' * 64
    exact = @version.artifacts.create!(identifier: 'exact', integrity: "sha256:#{digest}")
    @version.artifacts.create!(identifier: 'normalized', integrity: "sha256-#{digest}")

    get lookup_api_v1_artifacts_path(integrity: "sha256:#{digest}")

    assert_response :success
    response = Oj.load(@response.body)
    assert_equal [exact.id], response.pluck('id')
    assert_equal @package.name, response.first.dig('version', 'package', 'name')
    assert_equal @registry.name, response.first.dig('version', 'package', 'registry', 'name')
  end

  test 'lookup normalizes a known integrity wrapper after exact lookup misses' do
    digest = 'c' * 64
    artifact = @version.artifacts.create!(identifier: 'normalized', integrity: "sha256-#{digest}")

    get lookup_api_v1_artifacts_path(integrity: "SHA256:#{digest.upcase}")

    assert_response :success
    assert_equal [artifact.id], Oj.load(@response.body).pluck('id')
  end

  test 'lookup accepts an opaque integrity value' do
    artifact = @version.artifacts.create!(identifier: 'go-module', integrity: 'h1:AbCdEf==')

    get lookup_api_v1_artifacts_path(integrity: 'h1:AbCdEf==')

    assert_response :success
    assert_equal [artifact.id], Oj.load(@response.body).pluck('id')
  end

  test 'lookup preloads package maintainers' do
    maintainer = @registry.maintainers.create!(uuid: 'first', login: 'first')
    @package.maintainerships.create!(maintainer: maintainer)
    second_package = @registry.packages.create!(ecosystem: 'cargo', name: 'rand-core')
    second_version = second_package.versions.create!(number: '1.0.0', registry: @registry)
    second_maintainer = @registry.maintainers.create!(uuid: 'second', login: 'second')
    second_package.maintainerships.create!(maintainer: second_maintainer)
    second_version.artifacts.create!(identifier: 'rand-core-1.0.0.crate', integrity: @artifact.integrity)
    queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql if sql.include?('FROM "maintainerships"') || sql.include?('FROM "maintainers"')
    end

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      get lookup_api_v1_artifacts_path(integrity: @artifact.integrity)
    end

    assert_response :success
    assert_equal 2, queries.length
    assert_equal %w[first second], Oj.load(@response.body).flat_map { |artifact| artifact.dig('version', 'package', 'maintainers') }.pluck('login').sort
  end

  test 'lookup returns bad request without an integrity parameter' do
    get lookup_api_v1_artifacts_path

    assert_response :bad_request
    assert_equal 'Missing integrity, sha256, sha1, or sha512 parameter', Oj.load(@response.body)['error']
  end
end
