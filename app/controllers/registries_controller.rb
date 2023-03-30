class RegistriesController < ApplicationController
  def index
    redirect_to root_path
  end

  def show
    redirect_to registry_packages_path(params[:id])
  end

  def keywords
    @registry = Registry.find_by_name!(params[:id])
    @scope = @registry.keywords
    @pagy, @keywords = pagy_array(@scope)
  end

  def keyword
    @registry = Registry.find_by_name!(params[:id])
    @keyword = params[:keyword]
    scope = @registry.packages.where('keywords @> ARRAY[?]::varchar[]', @keyword)
    sort = params[:sort].presence || 'updated_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end
    
    @pagy, @packages = pagy_countless(scope)
    @related_keywords = (scope.pluck(:keywords).flatten - [@keyword]).inject(Hash.new(0)) { |h, e| h[e] += 1; h }.sort_by { |_, v| -v }.first(100)
  end
end