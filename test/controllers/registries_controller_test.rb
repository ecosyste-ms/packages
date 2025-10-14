require 'test_helper'

class RegistriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'npm', url: 'https://www.npmjs.com', ecosystem: 'npm')
  end

  test 'keywords action handles nil keywords gracefully' do
    # Simulate a scenario where keywords returns nil
    Registry.any_instance.stubs(:keywords).returns(nil)

    get keywords_registry_path(@registry.name)

    assert_response :success
    assert_template 'registries/keywords'
  end

  test 'keywords action renders successfully with valid keywords' do
    # Mock keywords to return an array of [keyword, count] pairs
    Registry.any_instance.stubs(:keywords).returns([['test-keyword', 5], ['another-keyword', 3]])

    get keywords_registry_path(@registry.name)

    assert_response :success
    assert_template 'registries/keywords'
  end

  test 'keywords action handles empty keywords array' do
    Registry.any_instance.stubs(:keywords).returns([])

    get keywords_registry_path(@registry.name)

    assert_response :success
    assert_template 'registries/keywords'
  end
end
