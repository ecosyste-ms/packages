class Api::V1::RegistriesController < Api::V1::ApplicationController
  def index
    @pagy, @registries = pagy(Registry.order('packages_count desc'))
  end
end