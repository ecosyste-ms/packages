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
      sort = params[:sort].presence || 'updated_at'
      sort = "(repo_metadata ->> 'stargazers_count')::text::integer" if params[:sort] == 'stargazers_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
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