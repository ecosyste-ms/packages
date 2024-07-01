class Dependency < ApplicationRecord
  belongs_to :version
  belongs_to :package, optional: true

  validates_presence_of :package_name, :version_id, :requirements, :ecosystem

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }

  scope :with_package, -> { where.not(package_id: nil) }
  scope :without_package, -> { where(package_id: nil) }

  def find_package_id
    registry = Registry.find_by_ecosystem(ecosystem)
    return unless registry
    registry.packages.find_by(name: package_name).try(:id)
  end

  def update_package_id
    return if package_id.present?
    p_id = find_package_id
    update(package_id: p_id) if p_id.present?
  end
end
