require 'faraday/typhoeus'
Faraday.default_adapter = :typhoeus

# Set default User-Agent for all Faraday connections
Faraday.default_connection_options = {
  headers: {
    'User-Agent' => 'packages.ecosyste.ms'
  }
}

ActiveSupport::Notifications.subscribe("request.faraday") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  host = event.payload[:url].host
  status = event.payload.response&.status || 0
  Appsignal.increment_counter("registry_http_requests", 1, host: host, status: status.to_s)
  Appsignal.add_distribution_value("registry_http_duration", event.duration, host: host)
end
