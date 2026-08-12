require 'faraday/typhoeus'
Faraday.default_adapter = :typhoeus

# Set default User-Agent for all Faraday connections
Faraday.default_connection_options = {
  headers: {
    'User-Agent' => 'packages.ecosyste.ms'
  }
}

# Faraday.get / Faraday.head / Faraday.post use this connection. Building it
# explicitly lets us include :instrumentation so those calls are counted by
# the request.faraday subscriber below alongside calls that go through
# Ecosystem::Base#request.
Faraday.default_connection = Faraday.new do |builder|
  builder.request :instrumentation
  builder.adapter Faraday.default_adapter
end

ActiveSupport::Notifications.subscribe("request.faraday") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  env = event.payload
  host = env[:url].host
  status = env[:status] || 0
  Appsignal.increment_counter("registry_http_requests", 1, host: host, status: status.to_s)
  Appsignal.add_distribution_value("registry_http_duration", event.duration, host: host)
rescue => e
  Rails.logger.warn("request.faraday subscriber error: #{e.class} #{e.message}")
end
