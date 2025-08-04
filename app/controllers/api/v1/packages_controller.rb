class Api::V1::PackagesController < Api::V1::ApplicationController

  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

    scope = scope.critical if params[:critical].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))
    fresh_when @packages, public: true
  end

  def critical
    scope = Package.active.critical
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

    scope = scope.with_funding if params[:funding].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))
    if stale?(@packages, public: true)
      render :index
    end
  end

  def critical_sole_maintainers
    scope = Package.critical.where(maintainers_count: 1).active.with_issue_metadata.sole_maintainer.includes(:registry, :maintainers)

    @registry = Registry.find_by_name(params[:registry]) if params[:registry]
    scope = scope.where(registry_id: @registry.id) if @registry

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

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
    if stale?(@packages, public: true)
      render :critical_sole_maintainers
    end
  end

  def lookup
    scope = Package.all
    if params[:id].present?
      @registry = Registry.find_by_name!(params[:id])
      scope = @registry.packages
    end

    if params[:repository_url].present?
      scope = scope.repository_url(params[:repository_url])
      scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    elsif params[:purl].present?
      scope = lookup_by_purl(params[:purl])
    else
      params[:name] = "library/#{params[:name]}" if params[:ecosystem] == 'docker' && !params[:name].include?('/')
      scope = scope.where(name: params[:name])
      scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    end

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    end

    @pagy, @packages = pagy_countless(scope.includes(:registry, {maintainers: :registry}))

    # if packages are not found, try to sync them
    if @packages.empty?
      if params[:purl].present?
        begin
          purl = Purl.parse(params[:purl])
          name = [purl.namespace, purl.name].compact.join(Ecosystem::Base.purl_type_to_namespace_separator(purl.type))
          ecosystem = Ecosystem::Base.purl_type_to_ecosystem(purl.type)
          registry = Registry.find_by_ecosystem(ecosystem)
          registry.sync_package_async(name) if registry
        rescue ArgumentError => e
          Rails.logger.error("ArgumentError in PURL parsing: #{e.message}")
          if e.message.include?("type is required")
            render json: { error: "Invalid PURL format (type is required): #{params[:purl]}" }, status: :unprocessable_content and return
          elsif e.message.downcase.include?('invalid')
            render json: { error: "Invalid PURL format: #{params[:purl]}" }, status: :unprocessable_content and return
          end
          raise e
        rescue Purl::MalformedUrlError, Purl::ValidationError => e
          Rails.logger.error("Purl error in PURL parsing: #{e.message}")
          render json: { error: "Invalid PURL format: #{params[:purl]}" }, status: :unprocessable_content and return
        end
      elsif params[:ecosystem].present? && params[:name].present?
        registry = Registry.find_by_ecosystem(params[:ecosystem])
        registry.sync_package_async(params[:name]) if registry
      end
    end

    fresh_when @packages, public: true
  end

  def bulk_lookup
    if params[:repository_urls].present?
      @packages = Package.repository_url(params[:repository_urls]).limit(1000)
    elsif params[:purls].present?
      @packages = Package.purl(params[:purls]).limit(1000)
    else
      @packages = Package.where(name: params[:names]).limit(1000)
    end
    @packages = @packages.includes(:registry, {maintainers: :registry})
    @packages = @packages.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
  end

  def names
    @registry = Registry.find_by_name!(params[:id])
    scope = @registry.packages
    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?
    scope = scope.critical if params[:critical].present?
    scope = scope.with_funding if params[:funding].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    end

    @pagy, @packages = pagy_countless(scope, limit_max: 10000)
    if stale?(@packages, public: true)
      render json: @packages.pluck(:name)
    end
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.includes(maintainerships: {maintainer: :registry}).find_by_name(params[:id])
    fresh_when @package, public: true
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

    if params[:latest].present?
      scope = @package.latest_dependent_packages(kind: params[:kind]).includes(:registry, {maintainers: :registry})
    else
      scope = @package.dependent_packages(kind: params[:kind]).includes(:registry, {maintainers: :registry})
    end

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    end

    @pagy, @packages = pagy_countless(scope)
    fresh_when @packages, public: true
  end

  def dependent_package_kinds
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])

    if params[:latest].present?
      @kinds = @package.latest_dependent_package_kinds
    else
      @kinds = @package.dependent_package_kinds
    end

    if stale?(@package, public: true)
      render json: @kinds
    end
  end

  def related_packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])

    scope = @package.related_packages.includes(:registry, {maintainers: :registry})

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort] || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    end

    @pagy, @packages = pagy_countless(scope)
    fresh_when @packages, public: true
  end

  def ping
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:id])
    if @package
      @package.sync_async
      @package.update_repo_metadata_async if request.user_agent&.include?('repos.ecosyste.ms')
      @package.update_advisories_async if request.user_agent&.include?('advisories.ecosyste.ms')
    else
      @registry.sync_package_async(params[:id])
    end
    render json: { message: 'pong' }
  end

  def ping_all
    unless params[:repository_url].nil?
      packages = Package.repository_url(params[:repository_url]).limit(1000)
      packages.each do |package|
        package.sync_async
        package.update_repo_metadata_async if request.user_agent&.include?('repos.ecosyste.ms')
        package.update_advisories_async if request.user_agent&.include?('advisories.ecosyste.ms')
      end
    end

    render json: { message: 'pong' }
  end
end