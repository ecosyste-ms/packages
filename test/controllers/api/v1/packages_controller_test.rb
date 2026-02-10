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

  test 'list package names with prefix filter' do
    @registry.packages.create(ecosystem: 'cargo', name: 'random-utils')
    @registry.packages.create(ecosystem: 'cargo', name: 'other-package')

    get package_names_api_v1_registry_path(id: @registry.name, prefix: 'ran')
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 2, actual_response.length
    assert_includes actual_response, 'rand'
    assert_includes actual_response, 'random-utils'
    refute_includes actual_response, 'other-package'
  end

  test 'list package names with prefix filter case insensitive' do
    @registry.packages.create(ecosystem: 'cargo', name: 'Random-Utils')

    get package_names_api_v1_registry_path(id: @registry.name, prefix: 'RAN')
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 2, actual_response.length
    assert_includes actual_response, 'rand'
    assert_includes actual_response, 'Random-Utils'
  end

  test 'list package names with postfix filter' do
    @registry.packages.create(ecosystem: 'cargo', name: 'my-rand')
    @registry.packages.create(ecosystem: 'cargo', name: 'other-package')

    get package_names_api_v1_registry_path(id: @registry.name, postfix: 'rand')
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 2, actual_response.length
    assert_includes actual_response, 'rand'
    assert_includes actual_response, 'my-rand'
    refute_includes actual_response, 'other-package'
  end

  test 'list package names with postfix filter case insensitive' do
    @registry.packages.create(ecosystem: 'cargo', name: 'my-RAND')

    get package_names_api_v1_registry_path(id: @registry.name, postfix: 'Rand')
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 2, actual_response.length
    assert_includes actual_response, 'rand'
    assert_includes actual_response, 'my-RAND'
  end

  test 'list package names with both prefix and postfix filters' do
    @registry.packages.create(ecosystem: 'cargo', name: 'rand-core')
    @registry.packages.create(ecosystem: 'cargo', name: 'my-rand-core')
    @registry.packages.create(ecosystem: 'cargo', name: 'rand-utils')

    get package_names_api_v1_registry_path(id: @registry.name, prefix: 'rand', postfix: 'core')
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 1, actual_response.length
    assert_includes actual_response, 'rand-core'
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

  test 'lookup by purl with repository_url qualifier returns only packages from specified registry' do
    # Create two Maven registries
    @maven_central = Registry.create(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven', default: true)
    @maven_google = Registry.create(name: 'maven.google.com', url: 'https://maven.google.com', ecosystem: 'maven', default: false)

    # Create the same package in both registries
    @package_central = @maven_central.packages.create(ecosystem: 'maven', name: 'com.example:library')
    @package_google = @maven_google.packages.create(ecosystem: 'maven', name: 'com.example:library')

    # Lookup by PURL with repository_url qualifier for maven.google.com
    get lookup_api_v1_packages_path(purl: 'pkg:maven/com.example/library@1.0?repository_url=https://maven.google.com')
    assert_response :success

    actual_response = Oj.load(@response.body)

    # Should return only the package from maven.google.com
    assert_equal 1, actual_response.length
    assert_equal 'maven.google.com', actual_response.first['registry']['name']
    assert_equal 'com.example:library', actual_response.first['name']
  end

  test 'lookup by purl without repository_url qualifier returns packages from all registries' do
    # Create two Maven registries
    @maven_central = Registry.create(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven', default: true)
    @maven_google = Registry.create(name: 'maven.google.com', url: 'https://maven.google.com', ecosystem: 'maven', default: false)

    # Create the same package in both registries
    @package_central = @maven_central.packages.create(ecosystem: 'maven', name: 'com.example:another')
    @package_google = @maven_google.packages.create(ecosystem: 'maven', name: 'com.example:another')

    # Lookup by PURL without repository_url qualifier
    get lookup_api_v1_packages_path(purl: 'pkg:maven/com.example/another@1.0')
    assert_response :success

    actual_response = Oj.load(@response.body)

    # Should return packages from both registries
    assert_equal 2, actual_response.length
    registry_names = actual_response.map { |p| p['registry']['name'] }.sort
    assert_equal ['maven.google.com', 'repo1.maven.org'], registry_names
  end

  test 'lookup by purl with repository_url qualifier normalizes URLs with trailing slashes' do
    # Create registry with trailing slash
    @maven_jitpack = Registry.create(name: 'jitpack.io', url: 'https://jitpack.io/', ecosystem: 'maven', default: false)
    @maven_central = Registry.create(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven', default: true)

    # Create packages
    @package_jitpack = @maven_jitpack.packages.create(ecosystem: 'maven', name: 'com.github:test')
    @package_central = @maven_central.packages.create(ecosystem: 'maven', name: 'com.github:test')

    # Lookup by PURL with repository_url WITHOUT trailing slash (should still match)
    get lookup_api_v1_packages_path(purl: 'pkg:maven/com.github/test@1.0?repository_url=https://jitpack.io')
    assert_response :success

    actual_response = Oj.load(@response.body)

    # Should return only the jitpack package due to URL normalization
    assert_equal 1, actual_response.length
    assert_equal 'jitpack.io', actual_response.first['registry']['name']
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

  test 'bulk_lookup by purls' do
    post bulk_lookup_api_v1_packages_path, params: { purls: ['pkg:cargo/rand'] }
    assert_response :success
    assert_template 'packages/bulk_lookup', file: 'packages/bulk_lookup.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal 1, actual_response.length
    assert_equal @package.name, actual_response.first['name']
  end

  test 'bulk_lookup by multiple purls' do
    second_package = @registry.packages.create(ecosystem: 'cargo', name: 'serde')

    post bulk_lookup_api_v1_packages_path, params: { purls: ['pkg:cargo/rand', 'pkg:cargo/serde'] }
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 2, actual_response.length
    names = actual_response.map { |p| p['name'] }
    assert_includes names, 'rand'
    assert_includes names, 'serde'
  end

  test 'bulk_lookup by repository_urls' do
    @package.update(repository_url: 'https://github.com/rust-random/rand')

    post bulk_lookup_api_v1_packages_path, params: { repository_urls: 'https://github.com/rust-random/rand' }
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 1, actual_response.length
    assert_equal @package.name, actual_response.first['name']
  end

  test 'bulk_lookup by names' do
    post bulk_lookup_api_v1_packages_path, params: { names: ['rand'] }
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 1, actual_response.length
    assert_equal @package.name, actual_response.first['name']
  end

  test 'bulk_lookup with invalid purls returns empty result' do
    post bulk_lookup_api_v1_packages_path, params: { purls: ['invalid-purl'] }
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 0, actual_response.length
  end

  test 'bulk_lookup returns error when more than 100 purls provided' do
    purls = (1..101).map { |i| "pkg:cargo/package#{i}" }

    post bulk_lookup_api_v1_packages_path, params: { purls: purls }
    assert_response :bad_request

    actual_response = Oj.load(@response.body)

    assert_equal "Maximum 100 PURLs allowed per request", actual_response['error']
  end

  test 'bulk_lookup filters by ecosystem' do
    npm_registry = Registry.create(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    npm_package = npm_registry.packages.create(ecosystem: 'npm', name: 'rand')

    post bulk_lookup_api_v1_packages_path, params: { names: ['rand'], ecosystem: 'npm' }
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal 1, actual_response.length
    assert_equal 'npm', actual_response.first['ecosystem']
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

  test 'list packages for a nixpkgs registry' do
    nix_registry = Registry.create(name: 'nixpkgs-23.05', url: 'https://channels.nixos.org/nixos-23.05', ecosystem: 'nixpkgs', version: '23.05')
    nix_registry.packages.create(ecosystem: 'nixpkgs', name: 'python313Packages.numpy', metadata: { 'position' => 'pkgs/development/python-modules/numpy/2.nix:205' })

    get api_v1_registry_packages_path(registry_id: nix_registry.name)
    assert_response :success

    actual_response = Oj.load(@response.body)
    assert_equal 1, actual_response.length
    assert_equal 'python313Packages.numpy', actual_response.first['name']
  end

  test 'get codemeta for a package' do
    get codemeta_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_template 'packages/codemeta', file: 'packages/codemeta.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response['@context'], 'https://w3id.org/codemeta/3.0'
    assert_equal actual_response['@type'], 'SoftwareSourceCode'
    assert_equal actual_response['identifier'], @package.purl
    assert_equal actual_response['name'], @package.name
    assert_equal actual_response['applicationCategory'], @package.ecosystem
  end

  test 'get codemeta for package with full metadata' do
    maintainer = Maintainer.create(
      login: 'test-maintainer',
      uuid: SecureRandom.uuid,
      url: 'https://github.com/test-maintainer',
      registry: @registry
    )

    @package.update(
      description: 'A random number generator',
      repository_url: 'https://github.com/rust-random/rand',
      homepage: 'https://rust-random.github.io/rand',
      normalized_licenses: ['MIT', 'Apache-2.0'],
      keywords_array: ['random', 'rng'],
      latest_release_number: '0.8.5',
      latest_release_published_at: 1.day.ago,
      first_release_published_at: 1.year.ago,
      dependent_repos_count: 100,
      repo_metadata: {
        'html_url' => 'https://github.com/rust-random/rand',
        'language' => 'Rust',
        'default_branch' => 'main',
        'stargazers_count' => 500,
        'forks_count' => 75,
        'metadata' => {
          'funding' => {
            'github' => ['rust-random']
          }
        }
      }
    )
    @package.maintainerships.create(maintainer: maintainer)

    get codemeta_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal actual_response['@context'], 'https://w3id.org/codemeta/3.0'
    assert_equal actual_response['@type'], 'SoftwareSourceCode'
    assert_equal actual_response['name'], 'rand'
    assert_equal actual_response['description'], 'A random number generator'
    assert_equal actual_response['version'], '0.8.5'
    assert_equal actual_response['codeRepository'], 'https://github.com/rust-random/rand'
    assert_equal actual_response['url'], 'https://rust-random.github.io/rand'
    assert_equal actual_response['issueTracker'], 'https://github.com/rust-random/rand/issues'
    assert_equal actual_response['keywords'], ['random', 'rng']
    assert_equal actual_response['license'], ['https://spdx.org/licenses/MIT', 'https://spdx.org/licenses/Apache-2.0']
    assert_equal actual_response['programmingLanguage']['@type'], 'ComputerLanguage'
    assert_equal actual_response['programmingLanguage']['name'], 'Rust'
    assert_equal actual_response['maintainer'].length, 1
    assert_equal actual_response['maintainer'].first['@type'], 'Person'
    assert_equal actual_response['maintainer'].first['name'], 'test-maintainer'
    assert_equal actual_response['maintainer'].first['url'], 'https://github.com/test-maintainer'
    assert_equal actual_response['author'].length, 1
    assert_equal actual_response['author'].first['name'], 'test-maintainer'
    assert_equal actual_response['copyrightHolder'].length, 1
    assert_equal actual_response['copyrightHolder'].first['name'], 'test-maintainer'
    assert_equal actual_response['developmentStatus'], 'active'
    assert_not_nil actual_response['dateCreated']
    assert_not_nil actual_response['dateModified']
    assert_not_nil actual_response['datePublished']
    assert_equal actual_response['copyrightYear'], 1.year.ago.year
    assert_equal actual_response['softwareVersion'], '0.8.5'
    assert_not_nil actual_response['sameAs']
    assert_includes actual_response['sameAs'], 'https://crates.io/crates/rand/'
    assert_equal actual_response['funder'].length, 1
    assert_equal actual_response['funder'].first['url'], 'https://github.com/sponsors/rust-random'
    assert_equal actual_response['https://www.w3.org/ns/activitystreams#likes'], 500
    assert_equal actual_response['https://forgefed.org/ns#forks'], 75
  end

  test 'get codemeta for pypi package with normalized name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'test-package',
      metadata: { 'normalized_name' => 'test-package' }
    )

    get codemeta_api_v1_registry_package_path(registry_id: pypi_registry.name, id: 'test_package')
    assert_response :success

    actual_response = Oj.load(@response.body)
    assert_equal actual_response['name'], 'test-package'
  end

  test 'get pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get api_v1_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success

    actual_response = Oj.load(@response.body)
    assert_equal 'tomli-w', actual_response['name']
  end

  test 'get dependent_packages for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get dependent_packages_api_v1_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get dependent_package_kinds for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get dependent_package_kinds_api_v1_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get related_packages for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get related_packages_api_v1_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get codemeta for docker library package' do
    docker_registry = Registry.create(name: 'hub.docker.com', url: 'https://hub.docker.com', ecosystem: 'docker')
    docker_package = docker_registry.packages.create(
      ecosystem: 'docker',
      name: 'library/python',
      namespace: 'library'
    )

    get codemeta_api_v1_registry_package_path(registry_id: docker_registry.name, id: 'python')
    assert_response :success

    actual_response = Oj.load(@response.body)
    assert_equal actual_response['name'], 'library/python'
  end

  test 'get codemeta omits fields when data is not present' do
    minimal_package = @registry.packages.create(
      ecosystem: 'cargo',
      name: 'minimal-package'
    )

    get codemeta_api_v1_registry_package_path(registry_id: @registry.name, id: minimal_package.name)
    assert_response :success

    actual_response = Oj.load(@response.body)

    # Should have required fields
    assert_equal actual_response['@context'], 'https://w3id.org/codemeta/3.0'
    assert_equal actual_response['@type'], 'SoftwareSourceCode'
    assert_equal actual_response['name'], 'minimal-package'
    assert_equal actual_response['applicationCategory'], 'cargo'
    assert_equal actual_response['runtimePlatform'], 'cargo'

    # Should not have optional fields when no explicit data
    assert_nil actual_response['description']
    assert_nil actual_response['version']
    assert_nil actual_response['softwareVersion']
    assert_nil actual_response['license']
    assert_nil actual_response['codeRepository']
    assert_nil actual_response['issueTracker']
    assert_nil actual_response['url']
    assert_nil actual_response['keywords']
    assert_nil actual_response['programmingLanguage']
    assert_nil actual_response['maintainer']
    assert_nil actual_response['author']
    assert_nil actual_response['copyrightHolder']
    assert_nil actual_response['dateCreated']
    assert_nil actual_response['dateModified']
    assert_nil actual_response['datePublished']
    assert_nil actual_response['copyrightYear']
    assert_nil actual_response['downloadUrl']
    assert_nil actual_response['funder']
    assert_nil actual_response['https://www.w3.org/ns/activitystreams#likes']
    assert_nil actual_response['https://forgefed.org/ns#forks']

    # Note: Some fields like sameAs and softwareHelp may be present for ecosystems
    # that have standard URL patterns (like cargo), so we don't assert they're nil
  end
end