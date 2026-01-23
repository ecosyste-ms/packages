require 'test_helper'

class FundingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'npm', url: 'https://www.npmjs.com', ecosystem: 'npm', packages_count: 100)
  end

  test 'show action renders when funded_packages_count is nil' do
    @registry.update(metadata: {})

    get funding_registry_path(@registry.name)

    assert_response :success
  end

  test 'show action renders when funded_packages_count is present' do
    @registry.update(metadata: { 'funded_packages_count' => 10 })

    get funding_registry_path(@registry.name)

    assert_response :success
  end
end
