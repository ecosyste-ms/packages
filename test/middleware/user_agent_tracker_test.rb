require 'test_helper'

class UserAgentTrackerTest < ActiveSupport::TestCase
  def setup
    @app = ->(env) { [200, {}, ['OK']] }
    @middleware = UserAgentTracker.new(@app)
  end

  test "tracks user agent for API requests" do
    env = {
      'PATH_INFO' => '/api/v1/packages',
      'HTTP_USER_AGENT' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)'
    }
    
    REDIS.expects(:zincrby).with("api_requests:#{Date.today}", 1, 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)')
    REDIS.expects(:expire).with("api_requests:#{Date.today}", 31.days.to_i)
    
    @middleware.call(env)
  end

  test "tracks unknown user agent when header is missing" do
    env = {
      'PATH_INFO' => '/api/v1/packages'
    }
    
    REDIS.expects(:zincrby).with("api_requests:#{Date.today}", 1, 'Unknown')
    REDIS.expects(:expire).with("api_requests:#{Date.today}", 31.days.to_i)
    
    @middleware.call(env)
  end

  test "does not track non-API requests" do
    env = {
      'PATH_INFO' => '/packages',
      'HTTP_USER_AGENT' => 'Mozilla/5.0'
    }
    
    REDIS.expects(:zincrby).never
    REDIS.expects(:expire).never
    
    @middleware.call(env)
  end

  test "handles nil PATH_INFO gracefully" do
    env = {
      'HTTP_USER_AGENT' => 'Mozilla/5.0'
    }
    
    REDIS.expects(:zincrby).never
    REDIS.expects(:expire).never
    
    @middleware.call(env)
  end

  test "handles Redis errors without failing the request" do
    env = {
      'PATH_INFO' => '/api/v1/packages',
      'HTTP_USER_AGENT' => 'TestAgent/1.0'
    }
    
    REDIS.expects(:zincrby).raises(Redis::ConnectionError)
    Rails.logger.expects(:error).with(includes('UserAgentTracker error:'))
    
    response = @middleware.call(env)
    assert_equal [200, {}, ['OK']], response
  end

  test "tracks different user agents separately" do
    env1 = {
      'PATH_INFO' => '/api/v1/packages',
      'HTTP_USER_AGENT' => 'curl/7.84.0'
    }
    
    env2 = {
      'PATH_INFO' => '/api/v1/versions',
      'HTTP_USER_AGENT' => 'PostmanRuntime/7.29.2'
    }
    
    REDIS.expects(:zincrby).with("api_requests:#{Date.today}", 1, 'curl/7.84.0')
    REDIS.expects(:zincrby).with("api_requests:#{Date.today}", 1, 'PostmanRuntime/7.29.2')
    REDIS.expects(:expire).with("api_requests:#{Date.today}", 31.days.to_i).twice
    
    @middleware.call(env1)
    @middleware.call(env2)
  end
end