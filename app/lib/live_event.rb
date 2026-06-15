module LiveEvent
  def self.enabled?
    ENV['LIVE_WEBHOOK_URL'].present?
  end

  def self.emit(events)
    return unless enabled?
    events = Array.wrap(events)
    return if events.empty?

    Faraday.post(ENV['LIVE_WEBHOOK_URL']) do |req|
      req.options.timeout = 2
      req.options.open_timeout = 2
      req.headers['Content-Type'] = 'application/json'
      req.headers['User-Agent'] = 'packages.ecosyste.ms'
      req.headers['Authorization'] = "Bearer #{ENV['LIVE_WEBHOOK_TOKEN']}" if ENV['LIVE_WEBHOOK_TOKEN'].present?
      req.body = { events: events }.to_json
    end
    nil
  rescue Faraday::Error, URI::InvalidURIError
    nil
  end
end
