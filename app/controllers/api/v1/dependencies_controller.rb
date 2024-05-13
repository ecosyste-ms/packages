class Api::V1::DependenciesController < Api::V1::ApplicationController
  def index
    scope = Dependency.all.includes(version: :package).order('id asc')

    scope = scope.where(ecosystem: params[:ecosystem]) if params[:ecosystem].present?
    scope = scope.where(package_id: params[:package_id]) if params[:package_id].present?
    scope = scope.where(package_name: params[:package_name]) if params[:package_name].present?
    scope = scope.where(requirements: params[:requirements]) if params[:requirements].present?
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    scope = scope.where(optional: params[:optional]) if params[:optional].present?
    scope = scope.where('dependencies.id > ?', params[:after]) if params[:after].present?

    @pagy, @dependencies = pagy_countless(scope)
    fresh_when(etag: @dependencies.map(&:id), public: true)
  end
end