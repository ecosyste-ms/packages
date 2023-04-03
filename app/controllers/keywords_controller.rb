class KeywordsController < ApplicationController
  def index
    @pagy, @keywords = pagy_array(Package.keywords)
  end

  def show
    @keyword = params[:id]

    scope = Package.active.includes(:registry).where('keywords @> ARRAY[?]::varchar[]', @keyword)

    @related_keywords = (scope.pluck(:keywords).flatten - [@keyword]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)

    scope = scope.order(Arel.sql("(rankings->>'average')::text::float").asc)
    
    @pagy, @packages = pagy_countless(scope)
  end
end