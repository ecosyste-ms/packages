class Dependency < ApplicationRecord
  belongs_to :version
  belongs_to :package, optional: true

  validates_presence_of :package_name, :version_id, :requirements, :ecosystem
end
