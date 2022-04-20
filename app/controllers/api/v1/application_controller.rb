class Api::V1::ApplicationController < ApplicationController
  after_action { pagy_headers_merge(@pagy) if @pagy }
end