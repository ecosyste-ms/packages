class RegistriesController < ApplicationController
  def index
    redirect_to root_path
  end

  def show
    redirect_to registry_packages_path(params[:id])
  end

  def keywords
    @registry = Registry.find_by_name!(params[:id])
    @keywords = @registry.keywords
  end
end