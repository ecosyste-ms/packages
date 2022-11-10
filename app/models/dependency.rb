class Dependency < ApplicationRecord
  belongs_to :version
  belongs_to :package, optional: true

  validates_presence_of :package_name, :version_id, :requirements, :ecosystem

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }

  scope :with_package, -> { where.not(package_id: nil) }
  scope :without_package, -> { where(package_id: nil) }
end
