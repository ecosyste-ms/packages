class ErrorsController < ApplicationController
  before_action :set_no_cache_headers

  def not_found
    respond_to do |format|
      format.html { render status: :not_found }
      format.json { render json: { error: "not found" }, status: :not_found }
      format.any { head :not_found }
    end
  end

  def unprocessable
    respond_to do |format|
      format.html { render status: :unprocessable_content }
      format.json { render json: { error: "unprocessable" }, status: :unprocessable_content }
      format.any { head :unprocessable_content }
    end
  end

  def internal
    respond_to do |format|
      format.html { render status: :internal_server_error }
      format.json { render json: { error: "internal server error" }, status: :internal_server_error }
      format.any { head :internal_server_error }
    end
  end

  private

  def set_no_cache_headers
    response.headers['Cache-Control'] = 'no-store'
  end
end
