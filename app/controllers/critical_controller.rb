class CriticalController < ApplicationController
  def index
    scope = Package.critical.includes(:registry)

    scope = scope.where(registry_id: Registry.find_by(name: params[:registry]).id) if params[:registry]

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

    @funding = scope.map{|p| p.funding_domains}.flatten.group_by(&:itself).map{|k, v| [k, v.count]}.to_h.sort_by{|k, v| v}.reverse.to_h

    @pagy, @packages = pagy(scope)

    @registries = Package.critical.group(:registry).count.sort_by{|r, c| r.name}
  end
end