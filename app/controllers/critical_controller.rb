class CriticalController < ApplicationController
  def index
    scope = Package.critical.includes(:registry)
    @pagy, @packages = pagy(scope.order('downloads DESC'))
    @registries = scope.group(:registry).count.sort_by{|r, c| -c}
  end
end