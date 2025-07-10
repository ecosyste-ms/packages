require 'test_helper'

class CriticalControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @maintainer = Maintainer.create(name: 'John Doe', uuid: SecureRandom.uuid, registry: @registry)
    
    @critical_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'critical-package', 
      critical: true,
      maintainers_count: 1,
      downloads: 1000,
      dependent_packages_count: 5,
      dependent_repos_count: 10,
      issue_metadata: {
        'past_year_issue_authors_count' => 25,
        'past_year_pull_request_authors_count' => 12,
        'past_year_issues_count' => 50,
        'past_year_pull_requests_count' => 30,
        'maintainers' => [{'login' => 'test-maintainer'}],
        'active_maintainers' => [{'login' => 'test-maintainer'}],
        'dds' => 0.85
      }
    )
    
    @critical_package.maintainers << @maintainer
    
    @non_critical_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'non-critical-package', 
      critical: false,
      maintainers_count: 1
    )
  end

  test 'should get sole maintainers index' do
    get critical_sole_maintainers_path
    assert_response :success
    assert_template 'critical/sole_maintainers'
  end

  test 'should show only critical packages with sole maintainers' do
    get critical_sole_maintainers_path
    assert_response :success
    assert_includes response.body, @critical_package.name
    assert_not_includes response.body, @non_critical_package.name
  end

  test 'should filter by registry' do
    other_registry = Registry.create(name: 'pypi', url: 'https://pypi.org', ecosystem: 'pypi')
    other_package = other_registry.packages.create(
      ecosystem: 'pypi', 
      name: 'other-package', 
      critical: true,
      maintainers_count: 1,
      issue_metadata: {
        'past_year_issue_authors_count' => 15,
        'dds' => 60
      }
    )
    
    get critical_sole_maintainers_path(registry: @registry.name)
    assert_response :success
    assert_includes response.body, @critical_package.name
    assert_not_includes response.body, other_package.name
  end

  test 'should sort packages by downloads desc by default' do
    high_download_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'high-download-package', 
      critical: true,
      maintainers_count: 1,
      downloads: 5000,
      issue_metadata: {
        'past_year_issue_authors_count' => 30,
        'dds' => 0.95
      }
    )
    
    get critical_sole_maintainers_path
    assert_response :success
    
    # Check that high download package appears before lower download package
    high_pos = response.body.index(high_download_package.name)
    low_pos = response.body.index(@critical_package.name)
    assert high_pos < low_pos
  end

  test 'should show maintainer information' do
    get critical_sole_maintainers_path
    assert_response :success
    assert_includes response.body, "DDS: 0.85"
  end

  test 'should show download counts when present' do
    get critical_sole_maintainers_path
    assert_response :success
    assert_includes response.body, "1 thousand downloads"
  end

  test 'should show dependent packages and repos counts' do
    get critical_sole_maintainers_path
    assert_response :success
    assert_includes response.body, "5 dependent packages"
    assert_includes response.body, "10 dependent repositories"
  end

  test 'should hide download counts when zero or nil' do
    @critical_package.update(downloads: 0)
    get critical_sole_maintainers_path
    assert_response :success
    # Look for the specific text pattern that would indicate download count display
    assert_not_includes response.body, "0 downloads"
    assert_not_includes response.body, "thousand downloads"
  end

  test 'should handle string values in issue metadata' do
    @critical_package.update(
      issue_metadata: {
        'past_year_issue_authors_count' => '25',  # String instead of integer
        'past_year_pull_request_authors_count' => '12',
        'maintainers' => [{'login' => 'test-maintainer'}],
        'active_maintainers' => [{'login' => 'test-maintainer'}],
        'dds' => '85'  # String DDS score
      }
    )
    get critical_sole_maintainers_path
    assert_response :success
    assert_includes response.body, "critical-package"
  end

  test 'should handle non-numeric string values in metadata' do
    @critical_package.update(
      issue_metadata: {
        'past_year_issue_authors_count' => 'invalid',  # Non-numeric string
        'past_year_pull_request_authors_count' => nil,
        'maintainers' => [{'login' => 'test-maintainer'}],
        'active_maintainers' => [{'login' => 'test-maintainer'}],
        'dds' => 'not_a_number'  # Non-numeric string DDS score
      }
    )
    get critical_sole_maintainers_path
    assert_response :success
    assert_includes response.body, "critical-package"
  end
end