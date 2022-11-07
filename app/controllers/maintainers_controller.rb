class MaintainersController < ApplicationController
  def index
    @registry = Registry.find_by!(name: params[:registry_id])
    @pagy, @maintainers = pagy_countless(@registry.maintainers.order('packages_count DESC'))
  end

  def show
    @registry = Registry.find_by!(name: params[:registry_id])
    @maintainer = @registry.maintainers.find_by!(login: params[:id])
    @pagy, @packages = pagy(@maintainer.packages.order('latest_release_published_at DESC'))
  end
end