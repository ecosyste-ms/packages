class Api::V1::NamespacesController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @pagy, @namespaces = pagy_array(@registry.packages.where.not(namespace: nil).group(:namespace).order('COUNT(id) desc').count.to_a)
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @namespace = params[:id]
    @packages_count = @registry.packages.namespace(@namespace).count
  end

  def packages
    @registry = Registry.find_by_name!(params[:registry_id])
    @namespace = params[:id]
    @pagy, @packages = pagy(@registry.packages.includes(:registry,{maintainers: :registry}).namespace(@namespace).order('latest_release_published_at DESC'))
  end
end