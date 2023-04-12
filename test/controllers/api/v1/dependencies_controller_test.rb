require 'test_helper'

class ApiV1DependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand')
    @version = @package.versions.create(number: '1.0.0', metadata: {foo: 'bar'})
    @dependency = @version.dependencies.create(ecosystem: 'cargo', package_name: 'rand', requirements: '1.0.0', kind: 'normal', optional: false)
  end

  test 'list dependencies for a package' do
    get api_v1_dependencies_url(package_name: 'rand')
    assert_response :success
    assert_equal 1, JSON.parse(@response.body).size  
  end
end