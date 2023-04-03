class KeywordsController < ApplicationController
  def index
    @pagy, @keywords = pagy_array(Package.keywords)
  end

  def show
    @keyword = params[:id]

    scope = Package.active.includes(:registry).where('keywords @> ARRAY[?]::varchar[]', @keyword)
    sort = params[:sort].presence || 'packages.updated_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end
    
    @pagy, @packages = pagy_countless(scope)
    @related_keywords = (scope.pluck(:keywords).flatten - [@keyword]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)
  end
end