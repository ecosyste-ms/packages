class ErrorsController < ApplicationController
  def not_found
    respond_to do |format|
      format.html { render status: :not_found }
      format.json { render json: { error: "not found" }, status: :not_found }
      format.any { head :not_found }
    end
  end

  def unprocessable
    respond_to do |format|
      format.html { render status: :unprocessable_entity }
      format.json { render json: { error: "unprocessable" }, status: :unprocessable_entity }
      format.any { head :unprocessable_entity }
    end
  end

  def internal
    respond_to do |format|
      format.html { render status: :internal_server_error }
      format.json { render json: { error: "internal server error" }, status: :internal_server_error }
      format.any { head :internal_server_error }
    end
  end
end
