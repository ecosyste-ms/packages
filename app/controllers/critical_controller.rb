class CriticalController < ApplicationController
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

    @funding = Rails.cache.fetch("critical:funding_domains:#{params[:registry]}", expires_in: 1.day) do
      scope.map{|p| p.funding_domains}.flatten.group_by(&:itself).map{|k, v| [k, v.count]}.to_h.sort_by{|k, v| v}.reverse.to_h
    end

    @pagy, @packages = pagy(scope)
    
    @registries = Rails.cache.fetch("critical:registries", expires_in: 1.day) do
      Package.critical.group(:registry).count.sort_by{|r, c| c}
    end
  end
end