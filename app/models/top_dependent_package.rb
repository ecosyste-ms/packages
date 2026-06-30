class TopDependentPackage < ApplicationRecord
  belongs_to :package

  LIMIT = 100
  THRESHOLD = 100

  SORTS = {
    'dependent_packages_count' => { order: 'dependent_packages_count DESC NULLS LAST', direction: :desc },
    'dependent_repos_count'    => { order: 'dependent_repos_count DESC NULLS LAST',    direction: :desc },
    'downloads'                => { order: 'downloads DESC NULLS LAST',                direction: :desc },
    'rank'                     => { order: "(rankings ->> 'average')::float ASC NULLS LAST", direction: :asc },
  }

  def self.cacheable_request?(params)
    return false unless SORTS.key?(params[:sort])
    return false if params[:latest] == 'false'
    return false if params[:kind].present?
    return false if params[:created_after].present? || params[:updated_after].present?
    return false if params[:min_stars].present? || params[:min_downloads].present?

    requested = params[:order] == 'asc' ? :asc : :desc
    requested == SORTS[params[:sort]][:direction]
  end
end
