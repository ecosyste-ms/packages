class VersionsController < ApplicationController
  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:package_id])
    @version = @package.versions.includes(:dependencies).find_by_number(params[:id])
  end

  def recent
    @registry = Registry.find_by_name!(params[:id])
    @pagy, @versions = pagy_countless(@registry.versions.order('published_at DESC, created_at DESC'))
  end
end