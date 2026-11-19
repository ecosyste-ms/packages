class Api::V1::ApplicationController < ApplicationController
  MAX_PAGE = 100

  before_action :set_api_cache_headers
  before_action :reject_deep_pagination
  after_action { pagy_headers_merge(@pagy) if @pagy }

  def default_url_options(options = {})
    Rails.env.production? ? { :protocol => "https" }.merge(options) : options
  end

  def set_api_cache_headers
    set_cache_headers(cdn_ttl: 1.hour)
  end

  def reject_deep_pagination
    return unless params[:page].to_i > MAX_PAGE
    render json: { error: "Pagination is capped at page #{MAX_PAGE}. Use the data exports at https://packages.ecosyste.ms/open-data for bulk access." }, status: :bad_request
  end
end
