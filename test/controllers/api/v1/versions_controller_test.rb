require 'test_helper'

class ApiV1VersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand')
    @version = @package.versions.create(number: '1.0.0', metadata: {foo: 'bar'}, registry_id: @registry.id)
  end

  test 'list versions for a package' do
    get api_v1_registry_package_versions_path(registry_id: @registry.name, package_id: @package.name)
    assert_response :success
    assert_template 'versions/index', file: 'packages/versions.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response.length, 1
  end

  test 'get version of a package' do
    get api_v1_registry_package_version_path(registry_id: @registry.name, package_id: @package.name, id: '1.0.0')
    assert_response :success
    assert_template 'versions/show', file: 'versions/show.json.jbuilder'
    
    actual_response = Oj.load(@response.body)

    assert_equal actual_response['number'], "1.0.0"
    assert_equal actual_response['metadata'], {"foo"=>"bar"}
  end

  test 'get recent versions' do
    get versions_api_v1_registry_path(id: @registry.name)
    assert_response :success
    assert_template 'versions/recent', file: 'versions/recent.json.jbuilder'

    actual_response = Oj.load(@response.body)

    first_version = actual_response.first

    assert_equal first_version['package_url'], api_v1_registry_package_url(registry_id: @registry.name, id: @package.name)
    assert_equal first_version['number'], "1.0.0"
    assert_equal first_version['metadata'], {"foo"=>"bar"}
  end

  test 'get recent versions excludes versions with invalid package_id' do
    dangling_version = @registry.versions.new(number: '2.0.0', package_id: 999_999, registry_id: @registry.id)
    dangling_version.save(validate: false)
  
    get versions_api_v1_registry_path(id: @registry.name)
    assert_response :success
    actual_response = Oj.load(@response.body)
  
    assert_equal 1, actual_response.length
    first_version = actual_response.first
    assert_equal first_version['number'], '1.0.0'
    assert_equal first_version['metadata'], { 'foo' => 'bar' }
  end

  test 'get version numbers' do
    get version_numbers_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal actual_response, ["1.0.0"]
  end

  test 'get codemeta for a version' do
    get codemeta_api_v1_registry_package_version_path(registry_id: @registry.name, package_id: @package.name, id: '1.0.0')
    assert_response :success
    assert_template 'versions/codemeta', file: 'versions/codemeta.json.jbuilder'

    actual_response = Oj.load(@response.body)

    assert_equal actual_response['@context'], 'https://w3id.org/codemeta/3.0'
    assert_equal actual_response['@type'], 'SoftwareSourceCode'
    assert_equal actual_response['identifier'], @version.purl
    assert_equal actual_response['name'], @package.name
    assert_equal actual_response['version'], '1.0.0'
    assert_equal actual_response['softwareVersion'], '1.0.0'
    assert_equal actual_response['applicationCategory'], @package.ecosystem
  end

  test 'get codemeta for version with full metadata' do
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
      keywords_array: ['random', 'rng'],
      language: 'Rust',
      normalized_licenses: ['MIT', 'Apache-2.0'],
      repo_metadata: {
        'html_url' => 'https://github.com/rust-random/rand',
        'default_branch' => 'master',
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

    @version.update(
      published_at: 1.year.ago,
      licenses: 'MIT'
    )

    get codemeta_api_v1_registry_package_version_path(registry_id: @registry.name, package_id: @package.name, id: '1.0.0')
    assert_response :success

    actual_response = Oj.load(@response.body)

    assert_equal actual_response['@context'], 'https://w3id.org/codemeta/3.0'
    assert_equal actual_response['@type'], 'SoftwareSourceCode'
    assert_equal actual_response['name'], 'rand'
    assert_equal actual_response['description'], 'A random number generator'
    assert_equal actual_response['version'], '1.0.0'
    assert_equal actual_response['softwareVersion'], '1.0.0'
    assert_equal actual_response['license'], 'https://spdx.org/licenses/MIT'
    assert_equal actual_response['codeRepository'], 'https://github.com/rust-random/rand'
    assert_equal actual_response['issueTracker'], 'https://github.com/rust-random/rand/issues'
    assert_equal actual_response['url'], 'https://rust-random.github.io/rand'
    assert_equal actual_response['keywords'], ['random', 'rng']
    assert_equal actual_response['programmingLanguage']['@type'], 'ComputerLanguage'
    assert_equal actual_response['programmingLanguage']['name'], 'Rust'
    assert_equal actual_response['maintainer'].length, 1
    assert_equal actual_response['maintainer'].first['@type'], 'Person'
    assert_equal actual_response['maintainer'].first['name'], 'test-maintainer'
    assert_equal actual_response['maintainer'].first['url'], 'https://github.com/test-maintainer'
    assert_equal actual_response['author'].length, 1
    assert_equal actual_response['copyrightHolder'].length, 1
    assert_equal actual_response['copyrightYear'], 1.year.ago.year
    assert_equal actual_response['applicationCategory'], 'cargo'
    assert_equal actual_response['runtimePlatform'], 'cargo'
    assert_equal actual_response['developmentStatus'], 'active'
    assert_equal actual_response['funder'].length, 1
    assert_equal actual_response['funder'].first['url'], 'https://github.com/sponsors/rust-random'
    assert_equal actual_response['https://www.w3.org/ns/activitystreams#likes'], 500
    assert_equal actual_response['https://forgefed.org/ns#forks'], 75
  end
end