class MaintainersController < ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])

    scope = @registry.maintainers

    if params[:sort].present? || params[:order].present?
      sort = sanitize_sort(Maintainer.sortable_columns, default: 'packages_count')
      if params[:order] == 'asc'
        scope = scope.order(sort.asc.nulls_last)
      else
        scope = scope.order(sort.desc.nulls_last)
      end
    else
      scope = scope.order('packages_count desc')
    end

    @pagy, @maintainers = pagy_countless(scope)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @maintainer = @registry.maintainers.find_by(login: params[:id]) || @registry.maintainers.find_by!(uuid: params[:id])

    raise ActiveRecord::RecordNotFound if @maintainer.blank?

    scope = @maintainer.packages.includes(:registry)

    if params[:sort].present? || params[:order].present?
      sort = sanitize_sort(Package.sortable_columns)
      if params[:order] == 'asc'
        scope = scope.order(sort.asc.nulls_last)
      else
        scope = scope.order(sort.desc.nulls_last)
      end
    else
      scope = scope.order('updated_at desc')
    end

    @pagy, @packages = pagy_countless(scope)
  end

  def namespaces
    @registry = Registry.find_by_name!(params[:registry_id])
    @maintainer = @registry.maintainers.find_by(login: params[:id]) || @registry.maintainers.find_by!(uuid: params[:id])
    @pagy, @namespaces = pagy_array(@maintainer.namespaces)
  end
end