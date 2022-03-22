class Version < ApplicationRecord
  validates_presence_of :package_id, :number
  validates_uniqueness_of :number, scope: :package_id

  belongs_to :package
  counter_culture :package
  has_many :dependencies, dependent: :delete_all
  has_many :runtime_dependencies, -> { where kind: %w[runtime normal] }, class_name: "Dependency"
end
