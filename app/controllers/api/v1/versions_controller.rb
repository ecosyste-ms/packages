class Api::V1::VersionsController < Api::V1::ApplicationController
  def index
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:package_id])
    scope = @package.versions#.includes(:dependencies)

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.published_after(params[:published_after]) if params[:published_after].present?
    scope = scope.published_before(params[:published_before]) if params[:published_before].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

    if params[:sort].present? || params[:order].present?
      sort = sanitize_sort(Version.sortable_columns, default: 'published_at')
      if params[:order] == 'asc'
        scope = scope.order(sort.asc.nulls_last)
      else
        scope = scope.order(sort.desc.nulls_last)
      end
    else
      scope = scope.order('published_at DESC nulls last, created_at DESC')
    end

    @pagy, @versions = pagy_countless(scope)
    fresh_when @versions, public: true
  end

  def show
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:package_id])
    @version = @package.versions.find_by_number!(params[:id])
    fresh_when @version, public: true
  end

  def recent
    @registry = Registry.find_by_name!(params[:id])

    scope = @registry.versions.includes(package: :registry).where("EXISTS (SELECT 1 FROM packages WHERE packages.id = versions.package_id)")

    scope = scope.created_after(params[:created_after]) if params[:created_after].present?
    scope = scope.published_after(params[:published_after]) if params[:published_after].present?
    scope = scope.published_before(params[:published_before]) if params[:published_before].present?
    scope = scope.updated_after(params[:updated_after]) if params[:updated_after].present?
    scope = scope.created_before(params[:created_before]) if params[:created_before].present?
    scope = scope.updated_before(params[:updated_before]) if params[:updated_before].present?

    if params[:sort].present? || params[:order].present?
      sort = sanitize_sort(Version.sortable_columns, default: 'published_at')
      if params[:order] == 'asc'
        scope = scope.order(sort.asc.nulls_last)
      else
        scope = scope.order(sort.desc.nulls_last)
      end
    else
      scope = scope.order('published_at DESC nulls last, created_at DESC')
    end

    @pagy, @versions = pagy_countless(scope)
  end

  def version_numbers
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:id])
    if stale?(@package, public: true)
      numbers = @package.versions.pluck(:number)
      render json: numbers
    end
  end

  def codemeta
    @registry = Registry.find_by_name!(params[:registry_id])
    @package = find_package_with_normalization!(@registry, params[:package_id])
    @version = @package.versions.find_by_number!(params[:id])
    fresh_when @version, public: true
  end

  def lookup
    integrity = params[:integrity]

    if integrity.blank?
      if params[:sha256].present?
        integrity = "sha256-#{params[:sha256]}"
      elsif params[:sha1].present?
        integrity = "sha1-#{params[:sha1]}"
      elsif params[:sha512].present?
        integrity = "sha512-#{params[:sha512]}"
      end
    end

    if integrity.present? && integrity.match?(/\A[a-fA-F0-9]+\z/)
      if integrity.length == 64
        integrity = "sha256-#{integrity}"
      elsif integrity.length == 40
        integrity = "sha1-#{integrity}"
      elsif integrity.length == 128
        integrity = "sha512-#{integrity}"
      end
    end

    if integrity.blank?
      return render json: { error: 'Missing integrity parameter' }, status: :bad_request
    end

    scope = Version.where(integrity: integrity).includes(package: :registry)

    @pagy, @versions = pagy_countless(scope)
  end
end