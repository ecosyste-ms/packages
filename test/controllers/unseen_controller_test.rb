require 'test_helper'

class UnseenControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'npmjs.org', url: 'https://npmjs.org', ecosystem: 'npm')

    @unseen_package = @registry.packages.create(
      ecosystem: 'npm',
      name: 'unseen-package',
      downloads: 150_000,
      repo_metadata: {
        'stargazers_count' => 50
      }
    )

    @popular_package = @registry.packages.create(
      ecosystem: 'npm',
      name: 'popular-package',
      downloads: 200_000,
      repo_metadata: {
        'stargazers_count' => 500
      }
    )

    @low_download_package = @registry.packages.create(
      ecosystem: 'npm',
      name: 'low-download-package',
      downloads: 50_000,
      repo_metadata: {
        'stargazers_count' => 10
      }
    )
  end

  test 'should get index' do
    get unseen_path
    assert_response :success
  end

  test 'should show packages with high downloads and low stars' do
    get unseen_path
    assert_response :success
    assert_includes response.body, @unseen_package.name
  end

  test 'should not show packages with high stars' do
    get unseen_path
    assert_response :success
    assert_not_includes response.body, @popular_package.name
  end

  test 'should not show packages with low downloads' do
    get unseen_path
    assert_response :success
    assert_not_includes response.body, @low_download_package.name
  end

  test 'should filter by registry' do
    other_registry = Registry.create(name: 'pypi', url: 'https://pypi.org', ecosystem: 'pypi')
    other_package = other_registry.packages.create(
      ecosystem: 'pypi',
      name: 'other-package',
      downloads: 200_000,
      repo_metadata: {
        'stargazers_count' => 30
      }
    )

    get unseen_path(registry: @registry.name)
    assert_response :success
    assert_includes response.body, @unseen_package.name
    assert_not_includes response.body, other_package.name
  end

  test 'should redirect from ecosystem to registry name' do
    get unseen_ecosystem_path(ecosystem: 'npm')
    assert_redirected_to unseen_path(registry: @registry.name)
  end

  test 'should return 404 when ecosystem not found' do
    get unseen_ecosystem_path(ecosystem: 'invalid-ecosystem')
    assert_response :not_found
  end

  test 'should cache registry counts' do
    # Enable caching for this test
    original_cache_store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.clear

    begin
      # First request should cache the registry counts
      get unseen_path
      assert_response :success

      cached_value = Rails.cache.read("unseen_registry_counts")
      assert_not_nil cached_value
      assert_equal({@registry.id => 1}, cached_value)

      # Create a new unseen package
      @registry.packages.create(
        ecosystem: 'npm',
        name: 'new-unseen-package',
        downloads: 160_000,
        repo_metadata: {
          'stargazers_count' => 60
        }
      )

      # Second request should use cached value, not reflect new package
      get unseen_path
      assert_response :success

      cached_value = Rails.cache.read("unseen_registry_counts")
      assert_equal({@registry.id => 1}, cached_value)
    ensure
      # Restore original cache store
      Rails.cache = original_cache_store
    end
  end
end
