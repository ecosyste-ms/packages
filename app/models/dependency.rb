class Dependency < ApplicationRecord
  RELINK_BATCH_SECONDS = 1
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

  def self.insert_linked(rows, registry:)
    names = rows.select { |row| row[:ecosystem] == registry.ecosystem }.map { |row| row[:package_name] }
    ids = Package.dependency_package_ids(registry.id, registry.ecosystem, names)
    linked = rows.map do |row|
      row.merge(package_id: (ids[row[:package_name]] if row[:ecosystem] == registry.ecosystem))
    end
    insert_all(linked)
    linked.filter_map { |row| row[:package_id] }.uniq
  end

  def self.relink_batch(registry:, name:, after_id: 0, batch_size: 1000)
    raise ArgumentError, 'batch_size must be between 1 and 1000' unless (1..1000).cover?(batch_size)
    raise ArgumentError, 'after_id must be non-negative' if after_id.negative?

    result = Package.with_dependency_query_limits do
      rows = without_package.where(ecosystem: registry.ecosystem, package_name: name)
                            .where('id > ?', after_id).order(:id).limit(batch_size).pluck(:id, :version_id)
      version_ids = Version.joins(:package).where(id: rows.map(&:last), packages: { registry_id: registry.id }).pluck(:id).to_set
      target_id = Package.dependency_package_ids(registry.id, registry.ecosystem, [name])[name]
      eligible_ids = rows.filter_map { |id, version_id| id if version_ids.include?(version_id) }
      linked = target_id ? without_package.where(id: eligible_ids).update_all(package_id: target_id) : 0
      { cursor: rows.last&.first || after_id, scanned: rows.length, linked: linked, target_id: target_id }
    end
    UpdateDependentPackagesCountWorker.enqueue([result[:target_id]]) if result[:linked].positive?
    result.except(:target_id)
  end

  def self.relink_missing_batch(after_id:, upper_id:, batch_size: 1000)
    raise ArgumentError, 'batch_size must be between 1 and 1000' unless (1..1000).cover?(batch_size)
    raise ArgumentError, 'invalid dependency bounds' unless after_id >= 0 && upper_id >= after_id

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + RELINK_BATCH_SECONDS
    with_connection do |connection|
      Package.with_dependency_query_limits do
        rows = connection.select_all(<<~SQL).to_a
          WITH page AS MATERIALIZED (
            SELECT id, version_id, package_id, ecosystem, package_name FROM dependencies
            WHERE id > #{Integer(after_id)} AND id <= #{Integer(upper_id)}
            ORDER BY id LIMIT #{Integer(batch_size)}
          )
          SELECT page.*, sources.registry_id, registries.ecosystem AS registry_ecosystem FROM page
          LEFT JOIN versions ON versions.id = page.version_id
          LEFT JOIN packages sources ON sources.id = versions.package_id
          LEFT JOIN registries ON registries.id = sources.registry_id
          ORDER BY page.id
        SQL
        cursor = after_id
        scanned = 0
        linked = 0
        package_ids = Set.new
        rows.chunk { |row| [row['registry_id'], row['registry_ecosystem']] }.each do |(registry_id, ecosystem), group|
          candidates = group.select do |row|
            row['package_id'].nil? && registry_id && row['ecosystem']&.casecmp?(ecosystem.to_s)
          end
          if candidates.any?
            targets = Package.dependency_package_ids(registry_id, ecosystem, candidates.map { |row| row['package_name'] })
            values = candidates.filter_map do |row|
              target_id = targets[row['package_name']]
              next unless target_id
              "(#{Integer(row['id'])}, #{Integer(target_id)}, #{Integer(row['version_id'])}, #{connection.quote(row['package_name'])}, #{connection.quote(row['ecosystem'])})"
            end
            if values.any?
              updated = connection.select_values(<<~SQL)
                UPDATE dependencies AS dependency SET package_id = resolved.package_id
                FROM (VALUES #{values.join(', ')}) AS resolved(id, package_id, version_id, package_name, ecosystem)
                WHERE dependency.id = resolved.id AND dependency.package_id IS NULL
                  AND dependency.version_id = resolved.version_id
                  AND dependency.package_name = resolved.package_name AND dependency.ecosystem = resolved.ecosystem
                RETURNING dependency.package_id
              SQL
              linked += updated.length
              package_ids.merge(updated)
            end
          end
          cursor = group.last.fetch('id')
          scanned += group.length
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        end
        complete = cursor >= upper_id || (scanned == rows.length && rows.length < batch_size)
        { cursor: cursor, scanned: scanned, linked: linked, package_ids: package_ids.to_a, complete: complete }
      end
    end
  end

  def find_package_id
    registry_id, registry_ecosystem = Version.joins(package: :registry).where(id: version_id).pick('packages.registry_id', 'registries.ecosystem')
    return unless registry_id && registry_ecosystem == ecosystem
    Package.dependency_package_id(registry_id, ecosystem, package_name)
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
          Package.dependency_package_id(registry_id, dependency.ecosystem, dependency.package_name)
        end

        next unless package_id
        dependency.update_column(:package_id, package_id)
      end
    end
  end
end
