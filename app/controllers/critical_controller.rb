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
    scope = Package.critical.where(maintainers_count: 1).active.with_issue_metadata.sole_maintainer.includes(:registry, :maintainers)

    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]

    scope = scope.where(registry_id: @registry.id) if params[:registry]

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'downloads'

      # Handle special sort fields that need SQL casting
      case params[:sort]
      when 'stargazers_count'
        sort = "(repo_metadata ->> 'stargazers_count')::text::integer"
      when 'name'
        sort = 'name'
      when 'versions_count'
        sort = 'versions_count'
      when 'latest_release_published_at'
        sort = 'latest_release_published_at'
      when 'dependent_packages_count'
        sort = 'dependent_packages_count'
      when 'dependent_repos_count'
        sort = 'dependent_repos_count'
      when 'downloads'
        sort = 'downloads'
      when 'maintainers_count'
        sort = 'maintainers_count'
      else
        sort = 'downloads' # fallback to safe default
      end

      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order_by_maintainer_count_asc.order('downloads DESC nulls last')
    end

    @pagy, @packages = pagy(scope)

    @registries = Package.critical.where(maintainers_count: 1).active.with_issue_metadata.sole_maintainer.group(:registry).count.sort_by{|r, c| c}
  end

  def maintainers
    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]

    # Build critical package subquery instead of plucking IDs
    critical_package_subquery = Package.critical.active.select(:id)
    critical_package_subquery = critical_package_subquery.where(registry_id: @registry.id) if params[:registry]

    # Get maintainer IDs and their package counts using subquery
    maintainer_id_counts = Maintainership.where(package_id: critical_package_subquery)
                                        .group(:maintainer_id)
                                        .count

    # Load maintainers with registry
    # Test in console: Maintainer.where(id: maintainer_id_counts.keys).includes(:registry).limit(10)
    maintainer_scope = Maintainer.where(id: maintainer_id_counts.keys).includes(:registry)

    # Sort in database if by login
    if params[:sort] == 'login'
      maintainer_scope = maintainer_scope.order(login: params[:order] == 'asc' ? :asc : :desc)
    end

    @pagy, maintainers_list = pagy(maintainer_scope)

    # Load packages for this page of maintainers using subquery
    # Test in console: paginated_ids = maintainers_list.map(&:id); Package.joins(:maintainerships).where(maintainerships: { maintainer_id: paginated_ids }).where(id: critical_package_subquery).includes(:registry).to_a
    paginated_ids = maintainers_list.map(&:id)

    # Get maintainerships for these maintainers and critical packages
    maintainerships_map = Maintainership.where(maintainer_id: paginated_ids, package_id: critical_package_subquery)
                                       .group_by(&:maintainer_id)

    package_ids_to_load = maintainerships_map.values.flatten.map(&:package_id).uniq
    packages_hash = Package.where(id: package_ids_to_load).includes(:registry).index_by(&:id)

    # Build packages by maintainer
    packages_by_maintainer_id = {}
    maintainerships_map.each do |maintainer_id, maintainerships|
      packages_by_maintainer_id[maintainer_id] = maintainerships.map { |m| packages_hash[m.package_id] }.compact.uniq
    end

    # Build maintainer data
    @maintainers = maintainers_list.map do |maintainer|
      packages = packages_by_maintainer_id[maintainer.id] || []

      {
        login: maintainer.login || maintainer.uuid,
        name: maintainer.name,
        registry: maintainer.registry,
        packages_count: maintainer_id_counts[maintainer.id],
        packages: packages.map do |package|
          {
            name: package.name,
            ecosystem: package.ecosystem,
            downloads: package.downloads,
            dependent_repos_count: package.dependent_repos_count,
            dependent_packages_count: package.dependent_packages_count,
            registry_name: package.registry.name
          }
        end
      }
    end

    # Sort by packages_count if needed
    if params[:sort] != 'login'
      @maintainers.sort_by! { |m| -m[:packages_count] }
      @maintainers.reverse! if params[:order] == 'asc'
    end

    # Registry counts using subquery
    registry_counts = Maintainer.joins(:maintainerships)
                                .where(maintainerships: { package_id: Package.critical.active.select(:id) })
                                .group(:registry_id)
                                .distinct
                                .count(:id)

    registries_hash = Registry.where(id: registry_counts.keys).index_by(&:id)
    @registries = registry_counts.map { |registry_id, count| [registries_hash[registry_id], count] }
                                 .sort_by { |r, c| -c }
  end

  def permit_scatter_params
    params.permit(:comparison_field)
  end
end