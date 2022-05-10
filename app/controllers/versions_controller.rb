class VersionsController < ApplicationController
  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:package_id])
    @version = @package.versions.find_by_number(params[:id])
  end
end