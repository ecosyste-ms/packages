require 'test_helper'

class Api::V1::SwiftpmLookupTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'swiftpackageindex.com', url: 'https://swiftpackageindex.com', ecosystem: 'swiftpm')
    @package = @registry.packages.create!(name: 'github.com/groue/GRDB.swift', ecosystem: 'swiftpm',
                                        metadata: {'normalized_name' => 'github.com/groue/grdb.swift'})
  end

  test 'lookup uses the canonical coordinate without changing repository punctuation' do
    get "/api/v1/registries/#{@registry.name}/packages/github.com%2FGROUE%2Fgrdb.swift"
    assert_response :success
    assert_equal @package.id, JSON.parse(response.body)['id']

    get "/api/v1/registries/#{@registry.name}/packages/github.com%2Fgroue%2FGRDB-swift"
    assert_response :not_found
  end

  test 'PURL lookup resolves casing variants without scheduling a sync' do
    other = Registry.create!(name: 'other', url: 'https://other.example', ecosystem: 'carthage')
    other.packages.create!(name: @package.name.downcase, ecosystem: 'carthage', metadata: @package.metadata)
    Registry.any_instance.expects(:sync_package_async).never

    get lookup_api_v1_packages_path, params: { purl: 'pkg:swift/github.com/GROUE/grdb.swift' }

    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')
  end

  test 'name lookup resolves casing variants within the selected ecosystem and registry' do
    other = Registry.create!(name: 'other', url: 'https://other.example', ecosystem: 'carthage')
    other.packages.create!(name: @package.name.downcase, ecosystem: 'carthage', metadata: @package.metadata)
    Registry.any_instance.expects(:sync_package_async).never

    get lookup_api_v1_packages_path, params: { ecosystem: 'swiftpm', name: @package.name.downcase }
    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')

    alternate = Registry.create!(name: 'alternate', url: 'https://swift.example', ecosystem: 'swiftpm')
    alternate.packages.create!(name: @package.name.downcase, ecosystem: 'swiftpm', metadata: @package.metadata)
    get lookup_api_v1_registry_path(id: @registry.name), params: { name: @package.name.upcase }
    assert_response :success
    assert_equal [@package.id], Oj.load(response.body).pluck('id')
  end

  test 'normalized PURL lookup preserves the repository qualifier' do
    alternate = Registry.create!(name: 'alternate', url: 'https://swift.example', ecosystem: 'swiftpm')
    package = alternate.packages.create!(name: @package.name.downcase, ecosystem: 'swiftpm', metadata: @package.metadata)
    Registry.any_instance.expects(:sync_package_async).never

    get lookup_api_v1_packages_path, params: {
      purl: 'pkg:swift/github.com/GROUE/grdb.swift?repository_url=https://swift.example'
    }

    assert_response :success
    assert_equal [package.id], Oj.load(response.body).pluck('id')
  end

  test 'PURL lookup preserves repository punctuation' do
    get lookup_api_v1_packages_path, params: { purl: 'pkg:swift/github.com/groue/GRDB-swift' }

    assert_response :success
    assert_empty Oj.load(response.body)
  end
end
