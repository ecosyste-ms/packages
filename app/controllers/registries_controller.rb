class RegistriesController < ApplicationController
  def index
    redirect_to root_path
  end

  def status
    @registries = Registry.not_docker.all.sort_by(&:outdated_percentage).reverse.select{|r| r.outdated_packages_count > 500 }
  end

  def show
    redirect_to registry_packages_path(params[:id])
  end

  def keywords
    @registry = Registry.find_by_name!(params[:id])
    @scope = @registry.keywords || []
    raise ActiveRecord::RecordNotFound if @scope.empty?
    @pagy, @keywords = pagy_array(@scope)
    @keywords ||= []
  end

  def keyword
    @registry = Registry.find_by_name!(params[:id])
    @keyword = params[:keyword]

    @related_keywords = Rails.cache.fetch(["related_keywords", @registry.id, @keyword], expires_in: 1.day) do
      @registry.packages.related_keywords(@keyword)
    end

    scope = @registry.packages.keyword(@keyword)
    if params[:sort].present? || params[:order].present?
      scope = scope.order(package_sort_order)
    else
      scope = scope.order('updated_at desc')
    end
    @pagy, @packages = pagy_countless(scope)
  end
end
