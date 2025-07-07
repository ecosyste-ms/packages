require 'test_helper'

class EcosystemsApiClientTest < ActiveSupport::TestCase
  class TestModel < ApplicationRecord
    include EcosystemsApiClient
    self.table_name = 'packages'
  end

  setup do
    @test_model = TestModel.new
  end

  test "ecosystems_api_get includes user agent header" do
    stub_request(:get, "https://example.ecosyste.ms/api/test")
      .with(headers: { 'User-Agent' => 'packages.ecosyste.ms' })
      .to_return(status: 200, body: '{"test": "data"}', headers: { 'Content-Type' => 'application/json' })

    result = @test_model.ecosystems_api_get("https://example.ecosyste.ms/api/test")
    
    assert_equal({ "test" => "data" }, result)
  end

  test "ecosystems_api_post includes user agent header" do
    stub_request(:post, "https://example.ecosyste.ms/api/test")
      .with(
        headers: { 
          'User-Agent' => 'packages.ecosyste.ms',
          'Content-Type' => 'application/json'
        },
        body: '{"key":"value"}'
      )
      .to_return(status: 200, body: '{"result": "success"}', headers: { 'Content-Type' => 'application/json' })

    result = @test_model.ecosystems_api_post("https://example.ecosyste.ms/api/test", { key: "value" })
    
    assert_equal({ "result" => "success" }, result)
  end

  test "ecosystems_api_get with params includes user agent header" do
    stub_request(:get, "https://example.ecosyste.ms/api/test?param1=value1&param2=value2")
      .with(headers: { 'User-Agent' => 'packages.ecosyste.ms' })
      .to_return(status: 200, body: '{"test": "data"}', headers: { 'Content-Type' => 'application/json' })

    result = @test_model.ecosystems_api_get("https://example.ecosyste.ms/api/test", params: { param1: "value1", param2: "value2" })
    
    assert_equal({ "test" => "data" }, result)
  end

  test "ecosystems_api_get returns nil on failure" do
    stub_request(:get, "https://example.ecosyste.ms/api/test")
      .with(headers: { 'User-Agent' => 'packages.ecosyste.ms' })
      .to_return(status: 404)

    result = @test_model.ecosystems_api_get("https://example.ecosyste.ms/api/test")
    
    assert_nil result
  end
end