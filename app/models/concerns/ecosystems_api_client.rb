module EcosystemsApiClient
  extend ActiveSupport::Concern

  class_methods do
    def ecosystems_api_get(url, options = {})
      response = Faraday.get(url) do |req|
        req.headers['User-Agent'] = 'packages.ecosyste.ms'
        req.headers.merge!(options[:headers] || {})
        req.params = options[:params] if options[:params]
      end
      
      return nil unless response.success?
      
      if options[:raw]
        response.body
      else
        JSON.parse(response.body)
      end
    rescue JSON::ParserError, Faraday::Error
      nil
    end

    def ecosystems_api_post(url, body = nil, options = {})
      response = Faraday.post(url) do |req|
        req.headers['User-Agent'] = 'packages.ecosyste.ms'
        req.headers['Content-Type'] = 'application/json'
        req.headers.merge!(options[:headers] || {})
        req.body = body.to_json if body
      end
      
      return nil unless response.success?
      
      if options[:raw]
        response.body
      else
        JSON.parse(response.body)
      end
    rescue JSON::ParserError, Faraday::Error
      nil
    end
  end

  def ecosystems_api_get(url, options = {})
    self.class.ecosystems_api_get(url, options)
  end

  def ecosystems_api_post(url, body = nil, options = {})
    self.class.ecosystems_api_post(url, body, options)
  end
end