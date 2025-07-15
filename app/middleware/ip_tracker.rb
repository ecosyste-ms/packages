class IpTracker
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
    ip_address = get_client_ip(env)
    today = Date.today.to_s
    
    # Use a sorted set for each day with IP addresses as members and counts as scores
    day_key = "api_requests:ips:#{today}"
    
    # Increment the count for this IP address
    REDIS.zincrby(day_key, 1, ip_address)
    
    # Set expiration to 31 days (30 days + today)
    # Redis will automatically delete the key when it expires
    REDIS.expire(day_key, 31.days.to_i)
  rescue => e
    Rails.logger.error "IpTracker error: #{e.message}"
  end

  def get_client_ip(env)
    # Check for Cloudflare's original IP header first
    cf_connecting_ip = env['HTTP_CF_CONNECTING_IP']
    return cf_connecting_ip.strip if cf_connecting_ip.present?
    
    # Check for forwarded IPs (when behind proxy/load balancer)
    forwarded_for = env['HTTP_X_FORWARDED_FOR']
    if forwarded_for.present?
      # Take the first IP if there are multiple (client -> proxy1 -> proxy2)
      forwarded_for.split(',').first.strip
    else
      # Direct connection
      env['REMOTE_ADDR'] || 'Unknown'
    end
  end
end