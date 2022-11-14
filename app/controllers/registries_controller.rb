class RegistriesController < ApplicationController
  def index
    redirect_to root_path
  end

  def show
    redirect_to registry_packages_path(params[:id])
  end
end