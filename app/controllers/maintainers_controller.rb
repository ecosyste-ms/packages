class MaintainersController < ApplicationController
  def index
    @registry = Registry.find_by!(name: params[:registry_id])

    scope = @registry.maintainers

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'packages_count'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('packages_count desc')
    end

    @pagy, @maintainers = pagy_countless(scope)
  end

  def show
    @registry = Registry.find_by!(name: params[:registry_id])
    @maintainer = @registry.maintainers.find_by(login: params[:id]) || @registry.maintainers.find_by!(uuid: params[:id])

    raise ActiveRecord::RecordNotFound if @maintainer.blank?

    scope = @maintainer.packages.includes(:registry)

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
  end

  def namespaces
    @registry = Registry.find_by!(name: params[:registry_id])
    @maintainer = @registry.maintainers.find_by(login: params[:id]) || @registry.maintainers.find_by!(uuid: params[:id])
    @pagy, @namespaces = pagy_array(@maintainer.namespaces)
  end
end