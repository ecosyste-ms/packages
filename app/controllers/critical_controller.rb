class CriticalController < ApplicationController
  def index
    scope = Package.critical.includes(:registry)

    scope = scope.where(registry_id: Registry.find_by(name: params[:registry]).id) if params[:registry]

    @pagy, @packages = pagy(scope.order('downloads DESC'))
    @registries = Package.critical.group(:registry).count.sort_by{|r, c| -c}
  end
end