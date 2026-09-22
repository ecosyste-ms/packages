require 'test_helper'

class ApiV1PypiLookupTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    @package = @registry.packages.create!(ecosystem: 'pypi', name: 'typing_extensions', metadata: { normalized_name: 'typing-extensions' })
    @names = ['typing-extensions', 'typing_extensions', 'Typing.Extensions', 'TYPING-._EXTENSIONS']
  end

  test 'global name lookup normalizes PyPI names and keeps the ecosystem restriction' do
    other = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    other.packages.create!(ecosystem: 'cargo', name: 'typing-extensions', metadata: @package.metadata)

    @names.each do |name|
      get lookup_api_v1_packages_path, params: { ecosystem: 'pypi', name: name }

      assert_response :success
      assert_equal [@package.id], Oj.load(response.body).pluck('id')
    end
  end

  test 'registry name lookup normalizes PyPI names with and without an ecosystem parameter' do
    alternate = Registry.create!(name: 'alternate-pypi', url: 'https://pypi.example', ecosystem: 'pypi')
    alternate.packages.create!(ecosystem: 'pypi', name: 'typing-extensions', metadata: @package.metadata)

    [{}, { ecosystem: 'pypi' }].each do |params|
      @names.each do |name|
        get lookup_api_v1_registry_path(id: @registry.name), params: params.merge(name: name)

        assert_response :success
        assert_equal [@package.id], Oj.load(response.body).pluck('id')
      end
    end
  end

  test 'single PURL lookup normalizes PyPI names and keeps the ecosystem restriction' do
    other = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    other.packages.create!(ecosystem: 'cargo', name: 'typing-extensions', metadata: @package.metadata)

    @names.each do |name|
      get lookup_api_v1_packages_path, params: { purl: "pkg:pypi/#{name}" }

      assert_response :success
      assert_equal [@package.id], Oj.load(response.body).pluck('id')
    end
  end

  test 'PyPI PURL lookup returns matches across registries without a repository qualifier' do
    alternate = Registry.create!(name: 'alternate-pypi', url: 'https://pypi.example', ecosystem: 'pypi')
    package = alternate.packages.create!(ecosystem: 'pypi', name: 'typing-extensions')

    get lookup_api_v1_packages_path, params: { purl: 'pkg:pypi/typing-extensions' }

    assert_response :success
    assert_equal [@package.id, package.id].sort, Oj.load(response.body).pluck('id').sort
  end

  test 'PyPI PURL normalization preserves repository_url qualifiers' do
    alternate = Registry.create!(name: 'alternate-pypi', url: 'https://pypi.example', ecosystem: 'pypi')
    package = alternate.packages.create!(ecosystem: 'pypi', name: @package.name, metadata: @package.metadata)

    get lookup_api_v1_packages_path, params: {
      purl: 'pkg:pypi/Typing.Extensions?repository_url=https://pypi.example'
    }

    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')

    get lookup_api_v1_packages_path, params: {
      purl: 'pkg:pypi/typing-extensions?repository_url=https://unknown.example'
    }

    assert_response :success
    assert_empty Oj.load(response.body)
  end

  test 'bulk PURL lookup normalizes PyPI names without duplicate results or cross-ecosystem matches' do
    other = Registry.create!(name: 'cocoapods.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods')
    package = other.packages.create!(ecosystem: 'cocoapods', name: 'MixedCase')
    other.packages.create!(ecosystem: 'cocoapods', name: 'mixedcase')
    other.packages.create!(ecosystem: 'cocoapods', name: 'typing-extensions', metadata: @package.metadata)
    second = @registry.packages.create!(ecosystem: 'pypi', name: 'azure_core', metadata: { normalized_name: 'azure-core' })

    @names.each do |name|
      post bulk_lookup_api_v1_packages_path, params: {
        purls: ["pkg:pypi/#{name}", "pkg:pypi/#{name}", 'pkg:pypi/Azure.Core', 'pkg:cocoapods/MixedCase']
      }

      assert_response :success
      assert_equal [@package.id, package.id, second.id].sort, Oj.load(response.body).pluck('id').sort
    end
  end

  test 'PyPI lookup retains exact and canonical name matches without normalized metadata' do
    @package.update_column(:metadata, {})
    canonical = @registry.packages.create!(ecosystem: 'pypi', name: 'azure-core')

    get lookup_api_v1_packages_path, params: { ecosystem: 'pypi', name: @package.name }
    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')

    get lookup_api_v1_packages_path, params: { ecosystem: 'pypi', name: 'Azure.Core' }
    assert_response :success
    assert_equal [canonical.id], Oj.load(response.body).pluck('id')

    get lookup_api_v1_packages_path, params: { purl: 'pkg:pypi/Azure.Core' }
    assert_response :success
    assert_equal [canonical.id], Oj.load(response.body).pluck('id')

    post bulk_lookup_api_v1_packages_path, params: { purls: ['pkg:pypi/Azure.Core'] }
    assert_response :success
    assert_equal [canonical.id], Oj.load(response.body).pluck('id')
  end

  test 'names with separator runs resolve through their canonical PURL' do
    package = @registry.packages.create!(ecosystem: 'pypi', name: 'foo__bar', metadata: { normalized_name: 'foo-bar' })

    get lookup_api_v1_packages_path, params: { purl: 'pkg:pypi/foo-bar' }
    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')

    assert_equal package, @registry.packages.find_by_normalized_name('foo-bar')
  end

  test 'package URLs resolve separator aliases before and after metadata normalization' do
    package = @registry.packages.create!(ecosystem: 'pypi', name: 'foo__bar', metadata: { normalized_name: 'foo--bar' })
    alternate = Registry.create!(name: 'alternate-pypi', url: 'https://pypi.example', ecosystem: 'pypi')
    alternate.packages.create!(ecosystem: 'pypi', name: package.name, metadata: package.metadata)

    ['foo--bar', 'foo-bar'].each do |normalized_name|
      package.update_column(:metadata, { 'normalized_name' => normalized_name })

      ['foo__bar', 'foo--bar', 'Foo..Bar'].each do |name|
        get api_v1_registry_package_path(registry_id: @registry.name, id: name)

        assert_response :success
        assert_equal package.id, Oj.load(response.body)['id']
      end
    end
  end

  test 'package URLs retain legacy normalized name matches without metadata' do
    package = @registry.packages.create!(ecosystem: 'pypi', name: 'foo--bar')

    get api_v1_registry_package_path(registry_id: @registry.name, id: 'Foo__Bar')

    assert_response :success
    assert_equal package.id, Oj.load(response.body)['id']
  end

  test 'PyPI normalization does not broaden lookups for missing packages' do
    get lookup_api_v1_packages_path, params: { ecosystem: 'pypi', name: 'Does.Not.Exist' }
    assert_response :success
    assert_empty Oj.load(response.body)

    get lookup_api_v1_packages_path, params: { purl: 'pkg:pypi/Does.Not.Exist' }
    assert_response :success
    assert_empty Oj.load(response.body)

    post bulk_lookup_api_v1_packages_path, params: { purls: ['pkg:pypi/Does.Not.Exist'] }
    assert_response :success
    assert_empty Oj.load(response.body)
  end
end
