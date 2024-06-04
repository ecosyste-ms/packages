class Api::V1::VersionsController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:package_id])
    @package = @registry.packages.find_by_name!(params[:package_id].downcase) if @package.nil?
    scope = @package.versions#.includes(:dependencies)

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.published_after(params[:published_after]) if params[:published_after].present?
    scope = scope.published_before(params[:published_before]) if params[:published_before].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'published_at'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('published_at DESC nulls last, created_at DESC')
    end

    @pagy, @versions = pagy_countless(scope)
    fresh_when @versions, public: true
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:package_id])
    @package = @registry.packages.find_by_name!(params[:package_id].downcase) if @package.nil?
    @version = @package.versions.find_by_number!(params[:id])
    fresh_when @version, public: true
  end

  def recent
    @registry = Registry.find_by_name!(params[:id])

    scope = @registry.versions.includes(package: :maintainers).joins(:package)

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.published_after(params[:published_after]) if params[:published_after].present?
    scope = scope.published_before(params[:published_before]) if params[:published_before].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'published_at'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('published_at DESC nulls last, created_at DESC')
    end

    @pagy, @versions = pagy_countless(scope)
    fresh_when @versions, public: true
  end

  def version_numbers
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name(params[:id])
    @package = @registry.packages.find_by_name!(params[:id].downcase) if @package.nil?
    if stale?(@package, public: true)
      numbers = @package.versions.pluck(:number)
      render json: numbers
    end
  end
end