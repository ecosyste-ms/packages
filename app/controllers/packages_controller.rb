class PackagesController < ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    scope = @registry.packages
    
    sort = params[:sort].presence || 'latest_release_published_at'
    if params[:order] == 'asc'
      scope = scope.order(Arel.sql(sort).asc.nulls_last)
    else
      scope = scope.order(Arel.sql(sort).desc.nulls_last)
    end
    
    @pagy, @packages = pagy_countless(scope)
  end

  def recent_versions_data
    @registry = Registry.find_by_name!(params[:registry_id])
    @recent_versions = @registry.versions.where('published_at > ?', 2.month.ago.beginning_of_day).where('published_at < ?', 1.day.ago.end_of_day).group_by_day(:published_at).count
    render json: @recent_versions
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])
    @pagy, @versions = pagy_countless(@package.versions.order('published_at DESC, created_at DESC'))
  end

  def dependent_packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])

    scope = @package.dependent_packages
    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'latest_release_published_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('latest_release_published_at DESC')
    end

    @pagy, @dependent_packages = pagy_countless(scope)
  end
end