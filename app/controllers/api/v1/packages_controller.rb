class Api::V1::PackagesController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))
  end

  def lookup
    if params[:repository_url].present?
      scope = Package.repository_url(params[:repository_url])
    elsif params[:purl].present?
      purl = PackageURL.parse(params[:purl])
      name = [purl.namespace, purl.name].compact.join(Ecosystem::Base.purl_type_to_namespace_seperator(purl.type))
      ecosystem = Ecosystem::Base.purl_type_to_ecosystem(purl.type) 
      scope = Package.where(name: name, ecosystem: ecosystem)
    else
      params[:name] = "library/#{params[:name]}" if params[:ecosystem] == 'docker' && !params[:name].include?('/')
      scope = Package.where(name: params[:name])
      scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    end

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))
  end

  def names
    @registry = Registry.find_by_name!(params[:id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope, max_items: 10000)
    render json: @packages.pluck(:name)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.includes(maintainerships: {maintainer: :registry}).find_by_name(params[:id])
    if @package.nil?
      # TODO: This is a temporary fix for pypi packages with underscores in their name
      # should redirect to the correct package name
      if @registry.ecosystem == 'pypi'
        @package = @registry.packages.find_by_normalized_name!(params[:id])
      elsif @registry.ecosystem == 'docker' && !params[:id].include?('/')
        @package = @registry.packages.find_by_name!("library/#{params[:id]}")
      else
        @package = @registry.packages.find_by_name!(params[:id].downcase)
      end
    end
  end

  def dependent_packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])

    scope = @package.dependent_packages.includes(:registry, {maintainers: :registry})

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      order = params[:order] || 'desc'
      sort_options = sort.split(',').zip(order.split(',')).to_h
      scope = scope.order(sort_options)
    end

    @pagy, @packages = pagy_countless(scope)
  end

  def related_packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])

    scope = @package.related_packages.includes(:registry, {maintainers: :registry})

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      order = params[:order] || 'desc'
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

  def ping_all
    Package.repository_url(params[:repository_url]).limit(1000).each(&:sync_async) unless params[:repository_url].nil?

    render json: { message: 'pong' }
  end
end