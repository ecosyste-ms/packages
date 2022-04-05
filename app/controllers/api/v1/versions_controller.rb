class Api::V1::VersionsController < Api::V1::ApplicationController
  def index
    @registry = Registry.find(params[:registry_id])
    @package = @registry.packages.find(params[:package_id])
    @pagy, @versions = pagy(@package.versions.includes(:dependencies).order('published_at desc, created_at desc'))
  end
end