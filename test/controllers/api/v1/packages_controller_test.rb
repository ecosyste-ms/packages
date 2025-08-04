require 'test_helper'

class ApiV1PackagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand', metadata: {foo: 'bar'})
  end

  test 'list packages for a registry' do
    get api_v1_registry_packages_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'packages/index', file: 'packages/index.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'list critical packages for a registry' do
    @critical_package = @registry.packages.create(ecosystem: 'cargo', name: 'semver', critical: true)
    get api_v1_registry_packages_path(registry_id: @registry.name, critical: true)
    assert_response :success
    assert_template 'packages/index', file: 'packages/index.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'list package names for a registry' do
    get package_names_api_v1_registry_path(id: @registry.name)
    assert_response :success
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first, @package.name
  end

  test 'get a package for a registry' do
    get api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_template 'packages/show', file: 'packages/show.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response["name"], @package.name
    assert_equal actual_response['metadata'], {"foo"=>"bar"}
  end

  test 'lookup by purl' do
    get lookup_api_v1_packages_path(purl: 'pkg:cargo/rand@0.8.0')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'lookup by purl with missing type' do
    invalid_purl = 'pkg:/software.amazon.awssdk%3Ametrics-spi'
  
    get lookup_api_v1_packages_path(purl: invalid_purl)
  
    assert_response :unprocessable_content
    actual_response = Oj.load(@response.body)
  
    assert_equal 'Invalid PURL format: pkg:/software.amazon.awssdk%3Ametrics-spi', actual_response['error']
  end

  test 'lookup by purl github actions' do
    @registry = Registry.create(name: 'github actions', url: 'https://github.com/marketplace/actions/', ecosystem: 'actions')
    @package = @registry.packages.create(ecosystem: 'actions', name: 'actions/checkout')

    get lookup_api_v1_packages_path(purl: 'pkg:githubactions/actions/checkout@v4')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'lookup by purl maven' do
    @registry = Registry.create(name: 'maven', url: 'https://mvnrepository.com/', ecosystem: 'maven')
    @package = @registry.packages.create(ecosystem: 'maven', name: 'org.apache.commons:commons-lang3')

    get lookup_api_v1_packages_path(purl: 'pkg:maven/org.apache.commons/commons-lang3@3.11')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'lookup by purl cocoapods with + in name' do
    @registry = Registry.create(name: 'cocoapods', url: 'https://cocoapods.org/', ecosystem: 'cocoapods')
    @package = @registry.packages.create(ecosystem: 'cocoapods', name: 'UIView+BooleanAnimations')

    get lookup_api_v1_packages_path(purl: 'pkg:cocoapods/UIView%2BBooleanAnimations')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'lookup by purl npm namespace' do
    @registry = Registry.create(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @package = @registry.packages.create(ecosystem: 'npm', name: '@loaders.gl/core', namespace: 'loaders.gl')

    get lookup_api_v1_packages_path(purl: 'pkg:npm/@loaders.gl/core')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'lookup by purl docker no namespace' do
    @registry = Registry.create(name: 'hub.docker.com', url: 'https://hub.docker.com', ecosystem: 'docker')
    @package = @registry.packages.create(ecosystem: 'docker', name: 'library/python', namespace: 'library')

    get lookup_api_v1_packages_path(purl: 'pkg:docker/python')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'lookup by purl github' do
    @registry = Registry.create(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @package = @registry.packages.create(ecosystem: 'npm', name: '@loaders.gl/core', namespace: 'loaders.gl', repository_url: 'https://github.com/visgl/loaders.gl')

    get lookup_api_v1_packages_path(purl: 'pkg:github/visgl/loaders.gl')
    assert_response :success
    assert_template 'packages/lookup', file: 'packages/lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], @package.name
  end

  test 'ping package' do
    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping package with repos.ecosyste.ms user agent' do
    # Mock the async methods to verify they're called
    Package.any_instance.expects(:sync_async).once
    Package.any_instance.expects(:update_repo_metadata_async).once

    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name),
        headers: { 'User-Agent' => 'repos.ecosyste.ms/1.0' }
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping package with different user agent' do
    # Mock the async methods to verify sync is called but not update_repo_metadata_async
    Package.any_instance.expects(:sync_async).once
    Package.any_instance.expects(:update_repo_metadata_async).never

    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name),
        headers: { 'User-Agent' => 'other-service/1.0' }
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping nonexistent package' do
    Registry.any_instance.expects(:sync_package_async).with('nonexistent').once

    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: 'nonexistent')
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping all packages by repository url' do
    @package.update(repository_url: 'https://github.com/rust-random/rand')
    
    Package.any_instance.expects(:sync_async).once
    Package.any_instance.expects(:update_repo_metadata_async).never

    get ping_api_v1_packages_path(repository_url: 'https://github.com/rust-random/rand')
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping all packages by repository url with repos.ecosyste.ms user agent' do
    @package.update(repository_url: 'https://github.com/rust-random/rand')
    
    Package.any_instance.expects(:sync_async).once
    Package.any_instance.expects(:update_repo_metadata_async).once

    get ping_api_v1_packages_path(repository_url: 'https://github.com/rust-random/rand'),
        headers: { 'User-Agent' => 'repos.ecosyste.ms/1.0' }
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping all packages without repository url' do
    get ping_api_v1_packages_path
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping package with advisories.ecosyste.ms user agent' do
    # Mock the async methods to verify they're called
    Package.any_instance.expects(:sync_async).once
    Package.any_instance.expects(:update_advisories_async).once

    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name),
        headers: { 'User-Agent' => 'advisories.ecosyste.ms/1.0' }
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'ping all packages by repository url with advisories.ecosyste.ms user agent' do
    @package.update(repository_url: 'https://github.com/rust-random/rand')
    
    Package.any_instance.expects(:sync_async).once
    Package.any_instance.expects(:update_advisories_async).once

    get ping_api_v1_packages_path(repository_url: 'https://github.com/rust-random/rand'),
        headers: { 'User-Agent' => 'advisories.ecosyste.ms/1.0' }
    assert_response :success
    
    actual_response = Oj.load(@response.body)
    assert_equal actual_response['message'], 'pong'
  end

  test 'list critical packages with sole maintainers' do
    maintainer = Maintainer.create(name: 'John Doe', uuid: SecureRandom.uuid, registry: @registry)
    
    critical_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'critical-sole-maintainer', 
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
    critical_package.maintainers << maintainer
    
    non_critical_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'non-critical-package', 
      critical: false,
      maintainers_count: 1
    )

    get critical_sole_maintainers_api_v1_packages_path
    assert_response :success
    assert_template 'api/v1/packages/critical_sole_maintainers'
    
    actual_response = Oj.load(@response.body)
    
    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], 'critical-sole-maintainer'
  end

  test 'list critical packages with sole maintainers filtered by registry' do
    other_registry = Registry.create(name: 'pypi', url: 'https://pypi.org', ecosystem: 'pypi')
    maintainer1 = Maintainer.create(name: 'John Doe', uuid: SecureRandom.uuid, registry: @registry)
    maintainer2 = Maintainer.create(name: 'Jane Doe', uuid: SecureRandom.uuid, registry: other_registry)
    
    critical_package1 = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'critical-sole-maintainer-1', 
      critical: true,
      maintainers_count: 1,
      issue_metadata: {
        'maintainers' => [{'login' => 'test-maintainer'}],
        'dds' => 0.85
      }
    )
    critical_package1.maintainers << maintainer1
    
    critical_package2 = other_registry.packages.create(
      ecosystem: 'pypi', 
      name: 'critical-sole-maintainer-2', 
      critical: true,
      maintainers_count: 1,
      issue_metadata: {
        'maintainers' => [{'login' => 'test-maintainer-2'}],
        'dds' => 0.90
      }
    )
    critical_package2.maintainers << maintainer2

    get critical_sole_maintainers_api_v1_packages_path(registry: @registry.name)
    assert_response :success
    assert_template 'api/v1/packages/critical_sole_maintainers'
    
    actual_response = Oj.load(@response.body)
    
    assert_equal actual_response.length, 1
    assert_equal actual_response.first['name'], 'critical-sole-maintainer-1'
  end

  test 'list critical packages with sole maintainers sorted by downloads' do
    maintainer = Maintainer.create(name: 'John Doe', uuid: SecureRandom.uuid, registry: @registry)
    
    high_download_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'high-download-package', 
      critical: true,
      maintainers_count: 1,
      downloads: 5000,
      issue_metadata: {
        'maintainers' => [{'login' => 'high-maintainer'}],
        'dds' => 0.95
      }
    )
    high_download_package.maintainers << maintainer
    
    low_download_package = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'low-download-package', 
      critical: true,
      maintainers_count: 1,
      downloads: 1000,
      issue_metadata: {
        'maintainers' => [{'login' => 'low-maintainer'}],
        'dds' => 0.85
      }
    )
    low_download_package.maintainers << maintainer

    get critical_sole_maintainers_api_v1_packages_path
    assert_response :success
    assert_template 'api/v1/packages/critical_sole_maintainers'
    
    actual_response = Oj.load(@response.body)
    
    assert_equal actual_response.length, 2
    assert_equal actual_response.first['name'], 'high-download-package'
    assert_equal actual_response.second['name'], 'low-download-package'
  end

  test 'list critical packages with sole maintainers with custom sort' do
    maintainer = Maintainer.create(name: 'John Doe', uuid: SecureRandom.uuid, registry: @registry)
    
    package_a = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'a-package', 
      critical: true,
      maintainers_count: 1,
      downloads: 1000,
      issue_metadata: {
        'maintainers' => [{'login' => 'a-maintainer'}],
        'dds' => 0.85
      }
    )
    package_a.maintainers << maintainer
    
    package_z = @registry.packages.create(
      ecosystem: 'cargo', 
      name: 'z-package', 
      critical: true,
      maintainers_count: 1,
      downloads: 2000,
      issue_metadata: {
        'maintainers' => [{'login' => 'z-maintainer'}],
        'dds' => 0.90
      }
    )
    package_z.maintainers << maintainer

    get critical_sole_maintainers_api_v1_packages_path(sort: 'name', order: 'asc')
    assert_response :success
    assert_template 'api/v1/packages/critical_sole_maintainers'
    
    actual_response = Oj.load(@response.body)
    
    assert_equal actual_response.length, 2
    assert_equal actual_response.first['name'], 'a-package'
    assert_equal actual_response.second['name'], 'z-package'
  end
end