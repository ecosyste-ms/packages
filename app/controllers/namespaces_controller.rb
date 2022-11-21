class NamespacesController < ApplicationController
  def index
    @registry = Registry.find_by!(name: params[:registry_id])
    @pagy, @namespaces = pagy_array(@registry.packages.where.not(namespace: nil).group(:namespace).order('COUNT(id)').count.to_a)
  end

  def show
    @registry = Registry.find_by!(name: params[:registry_id])
    @namespace = params[:id]
    @pagy, @packages = pagy(@registry.packages.namespace(@namespace).order('latest_release_published_at DESC'))
  end
end