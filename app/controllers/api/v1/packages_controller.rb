class Api::V1::PackagesController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'id'
      order = params[:order] || 'desc,desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))
  end

  def lookup
    if params[:repository_url].present?
      scope = Package.where(repository_url: params[:repository_url])
    else
      scope = Package.where(name: params[:name], ecosystem: params[:ecosystem])
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))
  end

  def names
    @registry = Registry.find_by_name!(params[:id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'id'
      order = params[:order] || 'desc,desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope, max_items: 10000)
    render json: @packages.pluck(:name)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:id])
    if @package.nil?
      # TODO: This is a temporary fix for pypi packages with underscores in their name
      # should redirect to the correct package name
      if @registry.ecosystem == 'pypi'
        @package = @registry.packages.find_by_name!(params[:id].downcase.gsub('_', '-'))
      else
        @package = @registry.packages.find_by_name!(params[:id].downcase)
      end
    end
  end

  def dependent_packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])

    scope = @package.dependent_packages

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'id'
      order = params[:order] || 'desc,desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope)
  end

  def ping
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:id])
    if @package
      @package.sync_async
    else
      @registry.sync_package_async(params[:id])
    end
    render json: { message: 'pong' }
  end
end