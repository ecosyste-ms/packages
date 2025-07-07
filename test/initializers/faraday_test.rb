require 'test_helper'

class FaradayInitializerTest < ActiveSupport::TestCase
  test "sets default User-Agent header for Faraday connections" do
    # Create a new Faraday connection without any custom headers
    conn = Faraday.new(url: 'https://example.com')
    
    # Check that the default User-Agent is set
    assert_equal 'packages.ecosyste.ms', conn.headers['User-Agent']
  end

  test "allows overriding default User-Agent header" do
    # Create a connection with custom User-Agent
    conn = Faraday.new(url: 'https://example.com') do |f|
      f.headers['User-Agent'] = 'custom-agent'
    end
    
    # Check that the custom User-Agent is used
    assert_equal 'custom-agent', conn.headers['User-Agent']
  end

  test "default User-Agent is applied to direct Faraday.get calls" do
    # Stub the request to check headers
    stub_request(:get, "https://example.com/test")
      .to_return(status: 200, body: "success")
    
    # Make a direct Faraday.get call
    response = Faraday.get('https://example.com/test')
    
    # Verify the request was made with the correct User-Agent
    assert_requested :get, "https://example.com/test",
      headers: { 'User-Agent' => 'packages.ecosyste.ms' }
  end

  test "default User-Agent is applied to direct Faraday.post calls" do
    # Stub the request to check headers
    stub_request(:post, "https://example.com/test")
      .with(body: "test data")
      .to_return(status: 200, body: "success")
    
    # Make a direct Faraday.post call
    response = Faraday.post('https://example.com/test', 'test data')
    
    # Verify the request was made with the correct User-Agent
    assert_requested :post, "https://example.com/test",
      headers: { 'User-Agent' => 'packages.ecosyste.ms' },
      body: "test data"
  end
end