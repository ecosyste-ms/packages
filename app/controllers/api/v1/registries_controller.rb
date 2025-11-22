class Api::V1::RegistriesController < Api::V1::ApplicationController
  def index
    scope = Registry.all
    scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    @pagy, @registries = pagy(scope.order('packages_count desc'))
    fresh_when @registries, public: true
  end

  def show
    @registry = Registry.find_by_name!(params[:id])
    fresh_when @registry, public: true
  end
end