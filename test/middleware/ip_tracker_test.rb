require 'test_helper'

class IpTrackerTest < ActiveSupport::TestCase
  def setup
    @app = ->(env) { [200, {}, ['OK']] }
    @middleware = IpTracker.new(@app)
  end

  test "tracks IP for API requests" do
    env = {
      'PATH_INFO' => '/api/v1/packages',
      'REMOTE_ADDR' => '192.168.1.100'
    }
    
    REDIS.expects(:zincrby).with("api_requests:ips:#{Date.today}", 1, '192.168.1.100')
    REDIS.expects(:expire).with("api_requests:ips:#{Date.today}", 31.days.to_i)
    
    @middleware.call(env)
  end

  test "tracks IP from X-Forwarded-For header when present" do
    env = {
      'PATH_INFO' => '/api/v1/packages',
      'HTTP_X_FORWARDED_FOR' => '10.0.0.1, 192.168.1.1',
      'REMOTE_ADDR' => '192.168.1.100'
    }
    
    REDIS.expects(:zincrby).with("api_requests:ips:#{Date.today}", 1, '10.0.0.1')
    REDIS.expects(:expire).with("api_requests:ips:#{Date.today}", 31.days.to_i)
    
    @middleware.call(env)
  end

  test "does not track non-API requests" do
    env = {
      'PATH_INFO' => '/packages',
      'REMOTE_ADDR' => '192.168.1.100'
    }
    
    REDIS.expects(:zincrby).never
    REDIS.expects(:expire).never
    
    @middleware.call(env)
  end

  test "handles missing IP address gracefully" do
    env = {
      'PATH_INFO' => '/api/v1/packages'
    }
    
    REDIS.expects(:zincrby).with("api_requests:ips:#{Date.today}", 1, 'Unknown')
    REDIS.expects(:expire).with("api_requests:ips:#{Date.today}", 31.days.to_i)
    
    @middleware.call(env)
  end

  test "handles Redis errors without failing the request" do
    env = {
      'PATH_INFO' => '/api/v1/packages',
      'REMOTE_ADDR' => '192.168.1.100'
    }
    
    REDIS.expects(:zincrby).raises(Redis::ConnectionError)
    Rails.logger.expects(:error).with(includes('IpTracker error:'))
    
    response = @middleware.call(env)
    assert_equal [200, {}, ['OK']], response
  end
end