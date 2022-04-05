class Api::V1::PackagesController < Api::V1::ApplicationController
  def index
    # paginated list of packages for a registry
    @registry = Registry.find(params[:registry_id])
    @pagy, @packages = pagy(@registry.packages.order('latest_release_published_at DESC, created_at DESC'))
  end

  def show
    @registry = Registry.find(params[:registry_id])
    @package = @registry.packages.find(params[:id])
  end
end