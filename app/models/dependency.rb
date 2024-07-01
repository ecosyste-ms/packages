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
    update_column(:package_id, p_id) if p_id.present?
  end

  def self.update_missing_package_ids
    registries = Registry.all.order('packages_count DESC').to_a
    processed_packages = {}
    without_package.find_each(order: :desc) do |dependency|
      registry = registries.select { |r| r.ecosystem == dependency.ecosystem }.first
      next unless registry

      # Modify the cache key to include both the registry id and the package name
      cache_key = "#{registry.id}_#{dependency.package_name}"

      # Directly assign the result of the lookup to the cache, caching nil results as well
      package_id = processed_packages[cache_key] = processed_packages.fetch(cache_key) do
        registry.packages.find_by(name: dependency.package_name)&.id
      end

      next unless package_id
      dependency.update_column(:package_id, package_id)
    end
  end
end
