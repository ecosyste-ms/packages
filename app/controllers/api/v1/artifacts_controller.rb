class Api::V1::ArtifactsController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:package_id])
    @version = @package.versions.find_by_number!(params[:version_id])
    scope = @version.artifacts.order('published_at DESC nulls last, id DESC')

    @pagy, @artifacts = pagy_countless(scope)
    fresh_when @artifacts, public: true
  end

  def show
    @artifact = Artifact.includes(version: { package: :registry }).find(params[:id])
    fresh_when @artifact, public: true
  end

  def lookup
    scope = Artifact.lookup(params)

    if scope.nil?
      return render json: { error: 'Missing integrity parameter' }, status: :bad_request
    end

    scope = scope.includes(version: [:dependencies, { package: :registry }])
                 .order('artifacts.published_at DESC nulls last, artifacts.id DESC')
    @pagy, @artifacts = pagy_countless(scope)
  end
end
