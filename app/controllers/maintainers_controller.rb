class MaintainersController < ApplicationController
  def index
    @registry = Registry.find_by!(name: params[:registry_id])
    @pagy, @maintainers = pagy(@registry.maintainers)
  end

  def show
    @registry = Registry.find_by!(name: params[:registry_id])
    @maintainer = @registry.maintainers.find_by!(login: params[:id])
    @pagy, @packages = pagy(@maintainer.packages)
  end
end