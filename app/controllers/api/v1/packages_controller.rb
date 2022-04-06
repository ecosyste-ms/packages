class Api::V1::PackagesController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @pagy, @packages = pagy(@registry.packages.order('latest_release_published_at DESC, created_at DESC'))
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:id])
  end
end