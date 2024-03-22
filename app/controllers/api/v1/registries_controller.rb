class Api::V1::RegistriesController < Api::V1::ApplicationController
  def index
    @pagy, @registries = pagy(Registry.order('packages_count desc'))
    fresh_when @registries, public: true
  end

  def show
    @registry = Registry.find_by_name!(params[:id])
    fresh_when @registry, public: true
  end
end