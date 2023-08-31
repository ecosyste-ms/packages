class Api::V1::VersionsController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:package_id])
    @package = @registry.packages.find_by_name!(params[:package_id].downcase) if @package.nil?
    scope = @package.versions#.includes(:dependencies)

    sort = params[:sort] || 'published_at,created_at'
    order = params[:order] || 'desc,desc'
    sort_options = sort.split(',').zip(order.split(',')).to_h

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.published_after(params[:published_after]) if params[:published_after].present?
    scope = scope.published_before(params[:published_before]) if params[:published_before].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    @pagy, @versions = pagy_countless(scope.order(sort_options))
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:package_id])
    @package = @registry.packages.find_by_name!(params[:package_id].downcase) if @package.nil?
    @version = @package.versions.find_by_number!(params[:id])
  end

  def recent
    @registry = Registry.find_by_name!(params[:id])

    sort = params[:sort] || 'published_at,created_at'
    order = params[:order] || 'desc,desc'
    sort_options = sort.split(',').zip(order.split(',')).to_h

    scope = @registry.versions#.includes(:package)
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.published_after(params[:published_after]) if params[:published_after].present?
    scope = scope.published_before(params[:published_before]) if params[:published_before].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    @pagy, @versions = pagy_countless(scope.order(sort_options))
  end
end