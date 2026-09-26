class MaintainersController < ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])

    scope = @registry.maintainers.visible

    if params[:sort].present? || params[:order].present?
      scope = scope.order(sanitize_sort(Maintainer, default: 'packages_count'))
    else
      scope = scope.order('packages_count desc')
    end

    @pagy, @maintainers = pagy_countless(scope)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    maintainers = @registry.maintainers.visible
    @maintainer = maintainers.find_by(login: params[:id]) || maintainers.find_by!(uuid: params[:id])

    raise ActiveRecord::RecordNotFound if @maintainer.blank?

    scope = @maintainer.packages.includes(:registry)

    if params[:sort].present? || params[:order].present?
      scope = scope.order(package_sort_order)
    else
      scope = scope.order('updated_at desc')
    end

    @pagy, @packages = pagy_countless(scope)
  end

  def namespaces
    @registry = Registry.find_by_name!(params[:registry_id])
    maintainers = @registry.maintainers.visible
    @maintainer = maintainers.find_by(login: params[:id]) || maintainers.find_by!(uuid: params[:id])
    @pagy, @namespaces = pagy_array(@maintainer.namespaces)
  end
end
