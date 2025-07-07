class UserAgentTracker
  def initialize(app)
    @app = app
  end

  def call(env)
    track_request(env) if api_request?(env)
    @app.call(env)
  end

  private

  def api_request?(env)
    env['PATH_INFO']&.start_with?('/api/')
  end

  def track_request(env)
    user_agent = env['HTTP_USER_AGENT'] || 'Unknown'
    today = Date.today.to_s
    
    # Use a sorted set for each day with user agents as members and counts as scores
    day_key = "api_requests:#{today}"
    
    # Increment the count for this user agent
    REDIS.zincrby(day_key, 1, user_agent)
    
    # Set expiration to 31 days (30 days + today)
    # Redis will automatically delete the key when it expires
    REDIS.expire(day_key, 31.days.to_i)
  rescue => e
    Rails.logger.error "UserAgentTracker error: #{e.message}"
  end
end