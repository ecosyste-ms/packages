class Api::V1::PurlsController < Api::V1::ApplicationController
  MAX_PURLS = 100

  def lookup
    if params[:purl].blank?
      return render json: { error: "Missing purl parameter" }, status: :bad_request
    end

    @result = PurlVersionLookup.new(params[:purl]).call
  end

  def bulk_lookup
    purls = Array(params[:purls])

    if purls.empty?
      return render json: { error: "Missing purls parameter" }, status: :bad_request
    end

    if purls.length > MAX_PURLS
      return render json: { error: "Maximum 100 PURLs allowed per request" }, status: :bad_request
    end

    @results = purls.map { |purl| PurlVersionLookup.new(purl).call }
  end
end
