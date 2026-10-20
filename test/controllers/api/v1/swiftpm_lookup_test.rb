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
end
