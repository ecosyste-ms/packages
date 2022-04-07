Rack::Attack.throttle("requests by ip", limit: 5000, period: 1.hour) do |request|
  request.ip
end