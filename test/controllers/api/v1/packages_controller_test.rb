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
  
    assert_response :unprocessable_entity
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
end