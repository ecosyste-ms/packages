class VersionsController < ApplicationController

  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:package_id])
    @pagy, @versions = pagy_countless(@package.versions.order('published_at DESC, created_at DESC'))
    fresh_when(@versions, public: true)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:package_id])
    @version = @package.versions.includes(:dependencies).find_by_number!(params[:id])
    fresh_when(@version, public: true)
  end

  def recent
    @registry = Registry.find_by_name!(params[:id])
    @pagy, @versions = pagy_countless(@registry.versions.joins(:package).order('published_at DESC, created_at DESC'))
    fresh_when(@versions, public: true)
  end
end