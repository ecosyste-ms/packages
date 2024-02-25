class CriticalController < ApplicationController
  def index
    scope = Package.critical.order('downloads DESC')
    @pagy, @packages = pagy(scope)
  end

  def show
    @registry = Registry.find_by!(name: params[:id])
    @pagy, @packages = pagy(@registry.packages.critical.order('downloads DESC'))
  end
end