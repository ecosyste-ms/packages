class Artifact < ApplicationRecord
  SYNC_ATTRIBUTES = %i[
    identifier
    filename
    kind
    download_url
    size
    published_at
    status
    integrity
    metadata
  ].freeze

  validates_presence_of :version_id, :identifier
  validates_uniqueness_of :identifier, scope: :version_id

  belongs_to :version

  def self.lookup(params)
    exact_integrity = params[:integrity].presence&.to_s
    normalized_integrity = Version.normalize_integrity(params)
    return if exact_integrity.blank? && normalized_integrity.blank?

    if exact_integrity.present?
      exact_matches = where(integrity: exact_integrity)
      return exact_matches if exact_matches.exists?
    end

    where(integrity: normalized_integrity)
  end
end
