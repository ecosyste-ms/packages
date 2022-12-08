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
    @recent_versions = Rails.cache.fetch("registry_recent_versions_data:#{@registry.id}", expires_in: 1.day) do
      @registry.versions.where('published_at > ?', 2.month.ago.beginning_of_day).where('published_at < ?', 1.day.ago.end_of_day).group_by_day(:published_at).count
    end
    render json: @recent_versions
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
    @pagy, @versions = pagy_countless(@package.versions.order('published_at DESC, created_at DESC'))
  end

  def dependent_packages
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

    scope = @package.dependent_packages.includes(:registry)
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

  def maintainers
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
    @pagy, @maintainers = pagy_countless(@package.maintainers)
  end
end