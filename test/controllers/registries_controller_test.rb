require 'test_helper'

class RegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'npm', url: 'https://www.npmjs.com', ecosystem: 'npm')
  end

  test 'keywords action returns 404 when keywords is nil' do
    # Simulate a scenario where keywords returns nil
    Registry.any_instance.stubs(:keywords).returns(nil)

    get keywords_registry_path(@registry.name)

    assert_response :not_found
  end

  test 'keywords action renders successfully with valid keywords' do
    # Mock keywords to return an array of [keyword, count] pairs
    Registry.any_instance.stubs(:keywords).returns([['test-keyword', 5], ['another-keyword', 3]])

    get keywords_registry_path(@registry.name)

    assert_response :success
    assert_template 'registries/keywords'
  end

  test 'keywords action returns 404 for empty keywords array' do
    Registry.any_instance.stubs(:keywords).returns([])

    get keywords_registry_path(@registry.name)

    assert_response :not_found
  end

  test 'keyword action renders packages without metadata' do
    registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go')
    package = registry.packages.create!(name: 'github.com/example/structures', ecosystem: 'go', keywords: ['structures'], metadata: nil)

    get keyword_registry_path(registry.name, 'structures')

    assert_response :success
    assert_select '.card-title a', text: package.name
    assert_select '[title="Accepts funding"]', count: 0
  end

  test 'keyword action shows repository funding without package metadata' do
    registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go')
    package = registry.packages.create!(
      name: 'github.com/example/structures', ecosystem: 'go', keywords: ['structures'], metadata: nil,
      repo_metadata: { 'metadata' => { 'funding' => { 'github' => 'example' } } }
    )

    get keyword_registry_path(registry.name, 'structures')

    assert_response :success
    assert_select '.card-title a', text: package.name
    assert_select '[title="Accepts funding"]', count: 1
  end
end
