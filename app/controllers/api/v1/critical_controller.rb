class Api::V1::CriticalController < Api::V1::ApplicationController
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

    @pagy, @packages = pagy_countless(scope)
    fresh_when @packages, public: true
  end

  def sole_maintainers
    scope = Package.critical.where(maintainers_count: 1).active.with_issue_metadata.sole_maintainer.includes(:registry, :maintainers)

    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]
    scope = scope.where(registry_id: @registry.id) if params[:registry]

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'downloads'

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
        sort = 'downloads'
      end

      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order_by_maintainer_count_asc.order('downloads DESC nulls last')
    end

    @pagy, @packages = pagy_countless(scope)
    fresh_when @packages, public: true
  end

  def maintainers
    @registry = Registry.find_by_name!(params[:registry]) if params[:registry]

    critical_package_subquery = Package.critical.active.select(:id)
    critical_package_subquery = critical_package_subquery.where(registry_id: @registry.id) if params[:registry]

    maintainer_id_counts = Maintainership.where(package_id: critical_package_subquery)
                                        .group(:maintainer_id)
                                        .count

    maintainer_scope = Maintainer.where(id: maintainer_id_counts.keys).includes(:registry)

    if params[:sort] == 'login'
      maintainer_scope = maintainer_scope.order(login: params[:order] == 'asc' ? :asc : :desc)
    end

    @pagy, maintainers_list = pagy_countless(maintainer_scope)

    paginated_ids = maintainers_list.map(&:id)

    maintainerships_map = Maintainership.where(maintainer_id: paginated_ids, package_id: critical_package_subquery)
                                       .group_by(&:maintainer_id)

    package_ids_to_load = maintainerships_map.values.flatten.map(&:package_id).uniq
    packages_hash = Package.where(id: package_ids_to_load).includes(:registry).index_by(&:id)

    packages_by_maintainer_id = {}
    maintainerships_map.each do |maintainer_id, maintainerships|
      packages_by_maintainer_id[maintainer_id] = maintainerships.map { |m| packages_hash[m.package_id] }.compact.uniq
    end

    @maintainers = maintainers_list.map do |maintainer|
      packages = packages_by_maintainer_id[maintainer.id] || []

      {
        login: maintainer.login || maintainer.uuid,
        name: maintainer.name,
        registry: maintainer.registry,
        packages_count: maintainer_id_counts[maintainer.id],
        packages: packages
      }
    end

    if params[:sort] != 'login'
      @maintainers.sort_by! { |m| -m[:packages_count] }
      @maintainers.reverse! if params[:order] == 'asc'
    end

    fresh_when maintainers_list, public: true
  end
end
