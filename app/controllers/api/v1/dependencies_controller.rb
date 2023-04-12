class Api::V1::DependenciesController < Api::V1::ApplicationController
  def index
    scope = Dependency.all.includes(version: :package)

    scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    scope = scope.where(package_id: params[:package_id]) if params[:package_id].present?
    scope = scope.where(package_name: params[:package_name]) if params[:package_name].present?
    scope = scope.where(requirement: params[:requirement]) if params[:requirement].present?
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    scope = scope.where(optional: params[:optional]) if params[:optional].present?

    @pagy, @dependencies = pagy_countless(scope)
  end
end