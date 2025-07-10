require 'matrix'

class CriticalController < ApplicationController
  def index
    scope = Package.critical.includes(:registry)

    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]

    scope = scope.where(registry_id: @registry.id) if params[:registry]

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'downloads'
      
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('downloads DESC nulls last')
    end

    @pagy, @packages = pagy(scope)
    
    @registries = Package.critical.group(:registry).count.sort_by{|r, c| c}
  end

  def scatter
    excluded_ecosystems = ['puppet', 'homebrew', 'nuget', 'docker']
    excluded_registry_ids = Registry.where(ecosystem: excluded_ecosystems).pluck(:id)
    scope = Package.critical.where.not(registry_id: excluded_registry_ids).where('packages.downloads > 0').includes(:registry).select('registry_id, packages.downloads, packages.dependent_repos_count, packages.dependent_packages_count, packages.docker_downloads_count, packages.docker_dependents_count, packages.repo_metadata')

    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]

    scope = scope.where(registry_id: @registry.id) if params[:registry]

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'downloads'
      
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      sort = "(repo_metadata ->> 'forks_count')::text::integer" if params[:sort] == 'forks_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('packages.downloads DESC nulls last')
    end

    @packages = scope.limit(9000)
    
    @comparison_field = params[:comparison_field].presence || 'dependent_repos_count'
    @valid_fields = ['dependent_repos_count', 'stargazers_count', 'forks_count', 'dependent_packages_count', 'docker_downloads_count', 'docker_dependents_count']
    
    unless @valid_fields.include?(@comparison_field)
      return render json: { error: 'Invalid comparison field' }, status: :bad_request
    end

    values = @packages.map { |pkg| [pkg.downloads, pkg.send(@comparison_field)] }.reject { |x, y| x.nil? || y.nil? || x == 0 || y == 0 }

    if values.size >= 2
      x_values, y_values = values.transpose
      mean_x = x_values.sum / x_values.size
      mean_y = y_values.sum / y_values.size

      covariance = x_values.zip(y_values).sum { |x, y| (x - mean_x) * (y - mean_y) } / x_values.size
      std_x = Math.sqrt(x_values.sum { |x| (x - mean_x) ** 2 } / x_values.size)
      std_y = Math.sqrt(y_values.sum { |y| (y - mean_y) ** 2 } / y_values.size)

      @correlation_coefficient = (std_x > 0 && std_y > 0) ? (covariance / (std_x * std_y)) : nil
    else
      @correlation_coefficient = nil
    end

    @registries = Package.where.not(registry_id: excluded_registry_ids).critical.where('packages.downloads > 0').group(:registry).count.sort_by{|r, c| c}
  end

  def sole_maintainers
    scope = Package.critical.where(maintainers_count: 1).includes(:registry, :maintainers)

    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]

    scope = scope.where(registry_id: @registry.id) if params[:registry]

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'downloads'
      
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('downloads DESC nulls last')
    end

    @pagy, @packages = pagy(scope)
    
    @registries = Package.critical.where(maintainers_count: 1).group(:registry).count.sort_by{|r, c| c}
  end

  def permit_scatter_params
    params.permit(:comparison_field)
  end
end