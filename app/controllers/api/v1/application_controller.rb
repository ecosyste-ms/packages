class Api::V1::ApplicationController < ApplicationController
  after_action { pagy_headers_merge(@pagy) if @pagy }

  after_action :set_rate_limit_headers!

  def set_rate_limit_headers!
    throttle_data = request.env['rack.attack.throttle_data']["requests by ip"]

    rate_limit_headers = {
      'x-ratelimit-limit' => throttle_data[:limit].to_s,
      'x-ratelimit-remaining' => (throttle_data[:limit] - throttle_data[:count]).to_s,
      'x-ratelimit-reset' => (throttle_data[:epoch_time] + (throttle_data[:period] - throttle_data[:epoch_time] % throttle_data[:period])).to_s
    }

    rate_limit_headers.each { |name, value| response.set_header(name, value) }
  end
end