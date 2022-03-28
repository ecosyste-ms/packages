class Api::V1::RegistriesController < Api::V1::ApplicationController
  def index
    @pagy, @registries = pagy(Registry.all)
  end
end