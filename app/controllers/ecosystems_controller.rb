class EcosystemsController < ApplicationController
  def index
    redirect_to root_path
  end

  def show
    @registries = Registry.where(ecosystem: params[:id]).order('packages_count desc, name desc').all
    @unique_packages_count = Package.where(registry_id: @registries.map(&:id)).distinct.count(:name)
    raise ActiveRecord::RecordNotFound if @registries.empty?
  end
end