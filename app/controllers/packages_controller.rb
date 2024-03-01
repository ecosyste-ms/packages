class PackagesController < ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    scope = @registry.packages

    if params[:keyword]
      scope = scope.keyword(params[:keyword])
    end
    
    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('updated_at DESC')
    end
    
    @pagy, @packages = pagy_countless(scope)
  end

  def recent_versions_data
    @registry = Registry.find_by_name!(params[:registry_id])
    @recent_versions = Rails.cache.fetch("registry_recent_versions_data:#{@registry.id}", expires_in: 1.day) do
      @registry.versions.where('published_at > ?', 1.month.ago.beginning_of_day).where('published_at < ?', 1.day.ago.end_of_day).group_by_day(:published_at).count
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
        @package = @registry.packages.find_by_normalized_name!(params[:id])
      elsif @registry.ecosystem == 'docker' && !params[:id].include?('/')
        @package = @registry.packages.find_by_name!("library/#{params[:id]}")
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
        @package = @registry.packages.find_by_normalized_name!(params[:id])
      elsif @registry.ecosystem == 'docker' && !params[:id].include?('/')
        @package = @registry.packages.find_by_name!("library/#{params[:id]}")
      else
        @package = @registry.packages.find_by_name!(params[:id].downcase)
      end
    end

    scope = @package.dependent_packages.includes(:registry)
    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'      
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
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
        @package = @registry.packages.find_by_normalized_name!(params[:id])
      elsif @registry.ecosystem == 'docker' && !params[:id].include?('/')
        @package = @registry.packages.find_by_name!("library/#{params[:id]}")
      else
        @package = @registry.packages.find_by_name!(params[:id].downcase)
      end
    end
    @pagy, @maintainers = pagy_countless(@package.maintainerships.includes(maintainer: :registry))
  end

  def related_packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:id])
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

    scope = @package.related_packages.includes(:registry)
    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('latest_release_published_at DESC')
    end

    @pagy, @related_packages = pagy_countless(scope)
  end

  def advisories
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:id])
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

  def lookup
    if params[:repository_url].present?
      scope = Package.repository_url(params[:repository_url])
    elsif params[:purl].present?
      scope = lookup_by_purl(params[:purl])
    else
      params[:name] = "library/#{params[:name]}" if params[:ecosystem] == 'docker' && !params[:name].include?('/')
      scope = Package.where(name: params[:name])
      scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    end

    @package = scope.first
    if @package.nil?
      raise ActiveRecord::RecordNotFound
    else
      redirect_to registry_package_path(@package.registry, @package)
    end
  end
end