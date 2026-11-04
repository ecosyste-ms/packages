module Cleanup
  class Packagist < Base
    STATE_KEY = 'packagist_cleanup'.freeze

    def validate_run
      raise ArgumentError, 'Expected a Packagist registry' unless @registry.ecosystem.casecmp?('packagist')
      name = @scope['name']
      raise ArgumentError, 'Invalid package NAME' if name && !name.match?(%r{\A[a-z0-9_.-]+/[a-z0-9_.-]+\z}i)
      unless @dry_run || @registry.metadata.to_h.dig(PackagistMalware::MALWARE_STATE_KEY, 'packages').is_a?(Hash)
        raise 'Run packages:sync_packagist_malware before applying the cleanup'
      end
    end

    def initial_counters
      {'platform_dependencies_removed' => 0}
    end

    def preview_package(package)
      {platform_dependencies: package ? platform_dependencies(package).sum(&:size) : 0}
    end

    def prepare_package(registry, package)
      metadata = registry.ecosystem_instance.package_metadata(package.name)
      registry.ecosystem_instance.fetch_malware_response(package.name.downcase) unless metadata
    end

    def repair_package(registry, package, missing_response)
      id = package.id
      package = registry.sync_package(package.name, force: true, maintenance: true)
      raise 'Packagist sync did not return the existing package' unless package.is_a?(Package) && package.id == id
      registry.ecosystem_instance.sync_malware(package.name.downcase, response: missing_response, package_id: id) if missing_response
      removed = remove_platform_dependencies(package)
      package = registry.packages.find(id)
      package.update!(versions_count: package.versions.count)
      package.update_details
      repair_dependency_links(package)
      {platform_dependencies_removed: removed}
    end

    def repair_dependency_links(package)
      dependencies = Dependency.where(version_id: package.versions.select(:id)).where('lower(ecosystem) = ?', 'packagist')
      dependencies.without_package.select(:id, :package_name).find_in_batches(batch_size: 1_000) do |batch|
        batch.group_by(&:package_name).each do |name, rows|
          target_id = Package.dependency_package_id(package.registry_id, 'packagist', name)
          next unless target_id

          dependencies.where(id: rows.map(&:id), package_id: nil).update_all(package_id: target_id)
        end
      end
      Package.where(id: dependencies.with_package.select(:package_id)).find_each do |target|
        target.update_dependent_packages_count
        target.update_top_dependent_packages
      end
    end

    def platform_dependencies(package)
      return enum_for(__method__, package) unless block_given?
      adapter = @registry.ecosystem_instance
      Dependency.where(version_id: package.versions.select(:id)).where('lower(ecosystem) = ?', 'packagist')
        .select(:id, :package_name, :package_id).find_in_batches(batch_size: 1_000) do |batch|
        yield batch.select { |dependency| adapter.platform_package?(dependency.package_name.to_s) }
      end
    end

    def remove_platform_dependencies(package)
      removed = 0
      platform_dependencies(package).each do |batch|
        next if batch.empty?
        removed += Dependency.where(id: batch.map(&:id)).delete_all
        Package.where(id: batch.map(&:package_id).compact.uniq).find_each do |target|
          target.update_dependent_packages_count
          target.update_top_dependent_packages
        end
      end
      removed
    end
  end
end
