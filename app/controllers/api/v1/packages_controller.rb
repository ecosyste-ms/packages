class Api::V1::PackagesController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'latest_release_published_at,created_at'
      order = params[:order] || 'desc,desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('latest_release_published_at DESC nulls last, created_at DESC')
    end

    @pagy, @packages = pagy(scope)
  end

  def names
    @registry = Registry.find_by_name!(params[:id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'latest_release_published_at,created_at'
      order = params[:order] || 'desc,desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    else
      scope = scope.order('latest_release_published_at DESC nulls last, created_at DESC')
    end

    @pagy, @packages = pagy(scope, max_items: 10000)
    render json: @packages.pluck(:name)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])
  end
end