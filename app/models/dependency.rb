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
    registry_id, registry_ecosystem = Version.joins(package: :registry).where(id: version_id).pick('packages.registry_id', 'registries.ecosystem')
    return unless registry_id && registry_ecosystem == ecosystem
    Package.where(registry_id: registry_id, name: package_name).pick(:id)
  end

  def update_package_id
    return if package_id.present?
    p_id = find_package_id
    update_column(:package_id, p_id) if p_id.present?
  end

  def self.update_missing_package_ids(batch_size: 1000)
    registry_ecosystems = Registry.pluck(:id, :ecosystem).to_h
    processed_packages = {}
    without_package.select(:id, :version_id, :ecosystem, :package_name).find_in_batches(batch_size: batch_size, order: :desc) do |dependencies|
      version_registry_ids = Version.joins(:package).where(id: dependencies.map(&:version_id).uniq).pluck(:id, 'packages.registry_id').to_h

      dependencies.each do |dependency|
        registry_id = version_registry_ids[dependency.version_id]
        next unless registry_id && registry_ecosystems[registry_id] == dependency.ecosystem

        cache_key = [registry_id, dependency.package_name]
        package_id = processed_packages[cache_key] = processed_packages.fetch(cache_key) do
          Package.where(registry_id: registry_id, name: dependency.package_name).pick(:id)
        end

        next unless package_id
        dependency.update_column(:package_id, package_id)
      end
    end
  end
end
