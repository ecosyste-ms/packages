class Api::V1::VersionsController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = @registry.packages.find_by_name!(params[:package_id])
    @pagy, @versions = pagy(@package.versions.includes(:dependencies).order('published_at desc, created_at desc'))
  end
end