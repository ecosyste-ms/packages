require 'test_helper'

class ApiV1KeywordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @registry.packages.create!(name: 'a', ecosystem: 'cargo', keywords: %w[cli json])
    @registry.packages.create!(name: 'b', ecosystem: 'cargo', keywords: %w[cli yaml])
  end

  test 'show returns packages and related keywords for a keyword' do
    get api_v1_keyword_path(id: 'cli')
    assert_response :success

    body = Oj.load(@response.body)
    assert_equal 2, body['packages'].length
    related = body['related_keywords'].map { |k| k['name'] }
    assert_includes related, 'json'
    assert_includes related, 'yaml'
    refute_includes related, 'cli'
  end
end
