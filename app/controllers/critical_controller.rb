class CriticalController < ApplicationController
  def index
    scope = Package.critical.includes(:registry)

    scope = scope.where(registry_id: Registry.find_by(name: params[:registry]).id) if params[:registry]

    @maintainers = scope.map(&:maintainers).flatten.group_by{|m| m }.map{|m, packages| [m, packages.length]}.to_h.sort_by{|m, c| -c}.first(100)

    if params[:maintainer].present?
      scope = scope.joins(:maintainers).where(maintainers: {uuid: params[:maintainer]})
    end

    if params[:sort].present? || params[:order].present?
      sort = params[:sort].presence || 'downloads'
      if params[:order] == 'asc'
        scope = scope.order(Arel.sql(sort).asc.nulls_last)
      else
        scope = scope.order(Arel.sql(sort).desc.nulls_last)
      end
    else
      scope = scope.order('downloads DESC')
    end

    @pagy, @packages = pagy(scope)

    @registries = Package.critical.group(:registry).count.sort_by{|r, c| r.name}
  end
end