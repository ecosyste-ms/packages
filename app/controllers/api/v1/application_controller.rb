class Api::V1::ApplicationController < ApplicationController
  after_action { pagy_headers_merge(@pagy) if @pagy }

  def default_url_options(options = {})
    Rails.env.production? ? { :protocol => "https" }.merge(options) : options
  end
end