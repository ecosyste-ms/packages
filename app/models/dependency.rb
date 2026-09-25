class Dependency < ApplicationRecord
  belongs_to :version
  belongs_to :package, optional: true

  def self.sortable_columns
    {
      'id' => 'id',
      'created_at' => 'created_at',
      'updated_at' => 'updated_at',
      'package_name' => 'package_name',
      'ecosystem' => 'ecosystem',
      'kind' => 'kind',
    }
  end

  validates_presence_of :package_name, :version_id, :requirements, :ecosystem

  scope :ecosystem, ->(ecosystem) { where(ecosystem: ecosystem.downcase) }

  scope :with_package, -> { where.not(package_id: nil) }
  scope :without_package, -> { where(package_id: nil) }

  def find_package_id
    registry = version&.package&.registry
    return unless registry && registry.ecosystem == ecosystem
    registry.packages.find_by(name: package_name).try(:id)
  end

  def update_package_id
    return if package_id.present?
    p_id = find_package_id
    update_column(:package_id, p_id) if p_id.present?
  end

  def self.update_missing_package_ids
    processed_packages = {}
    without_package.includes(version: { package: :registry }).find_each(order: :desc) do |dependency|
      registry_id = dependency.version&.package&.registry_id
      cache_key = [registry_id, dependency.ecosystem, dependency.package_name]

      package_id = processed_packages[cache_key] = processed_packages.fetch(cache_key) do
        dependency.find_package_id
      end

      next unless package_id
      dependency.update_column(:package_id, package_id)
    end
  end
end
