class NamespacesController < ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @pagy, @namespaces = pagy_array(@registry.packages.where.not(namespace: nil).group(:namespace).order('COUNT(id) desc').count.to_a)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @namespace = params[:id]

    scope = @registry.packages.namespace(@namespace)

    if params[:sort].present? || params[:order].present?
      scope = scope.order(package_sort_order)
    else
      scope = scope.order('updated_at desc')
    end

    @pagy, @packages = pagy_countless(scope)
    fresh_when(@packages, public: true)
  end

  def maintainers
    @registry = Registry.find_by_name!(params[:registry_id])
    @namespace = params[:id]
    @scope = @registry.namespace_maintainers(@namespace)
    @pagy, @maintainers = pagy_countless(@scope)
    fresh_when(@maintainers, public: true)
  end
end
