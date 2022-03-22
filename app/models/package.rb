class Package < ApplicationRecord
  validates_presence_of :registry_id, :name, :ecosystem
  validates_uniqueness_of :name, scope: :ecosystem, case_sensitive: true

  belongs_to :registry
  has_many :versions
  has_many :dependencies, -> { group 'package_name' }, through: :versions
end
