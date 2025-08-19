class TransitiveDependencyResolver
  class DependencyResolutionError < StandardError; end
  
  DEFAULT_MAX_DEPTH = 10
  DEFAULT_MAX_DEPENDENCIES = 30
  CACHE_TTL = 24.hours

  def self.for_ecosystem(ecosystem)
    resolver_class_name = "#{ecosystem.classify}TransitiveDependencyResolver"
    resolver_class = resolver_class_name.safe_constantize
    resolver_class || self
  end

  def initialize(version, max_depth: DEFAULT_MAX_DEPTH, max_dependencies: DEFAULT_MAX_DEPENDENCIES, include_optional: false, kind: nil)
    @version = version
    @package = version.package
    @registry = @package.registry
    @max_depth = max_depth
    @max_dependencies = max_dependencies
    @include_optional = include_optional
    @kind = kind
    @visited_packages = Set.new
  end

  def resolve
    cache_key = build_cache_key
    
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
      result = resolve_dependencies(@version, 0)
      
      if result.length > @max_dependencies
        raise DependencyResolutionError.new(
          "Too many dependencies: #{result.length} exceeds limit of #{@max_dependencies}"
        )
      end
      
      result
    end
  end

  private

  def resolve_dependencies(version, current_depth)
    return [] if current_depth >= @max_depth
    
    package_key = "#{version.package.name}:#{version.number}"
    return [] if @visited_packages.include?(package_key)
    
    @visited_packages.add(package_key)
    
    direct_dependencies = get_filtered_dependencies(version)
    all_dependencies = []
    
    direct_dependencies.each do |dependency|
      dependency_package = find_dependency_package(dependency)
      next unless dependency_package
      
      matching_version = find_matching_version(dependency_package, dependency.requirements)
      next unless matching_version
      
      dependency_package_key = "#{matching_version.package.name}:#{matching_version.number}"
      next if @visited_packages.include?(dependency_package_key)
      
      all_dependencies << dependency
      all_dependencies.concat(
        resolve_dependencies(matching_version, current_depth + 1)
      )
    end
    
    @visited_packages.delete(package_key)
    merge_duplicate_dependencies(all_dependencies)
  end

  def get_filtered_dependencies(version)
    version.dependencies.select do |dependency|
      (@kind.blank? || dependency.kind == @kind) &&
      (@include_optional || !dependency.optional)
    end
  end

  def find_dependency_package(dependency)
    @registry.packages.find_by(name: dependency.package_name)
  end

  def find_matching_version(package, requirements)
    normalized_requirements = normalize_version_requirements(requirements)
    
    matching_versions = package.versions.active.select do |version|
      version_matches_requirements?(version, normalized_requirements)
    end
    
    if matching_versions.empty?
      raise DependencyResolutionError.new(
        "No version of '#{package.name}' satisfies requirements: #{requirements}"
      )
    end
    
    select_best_version(matching_versions)
  end

  def select_best_version(matching_versions)
    matching_versions.sort.first
  end

  def normalize_version_requirements(requirements)
    requirements
  end

  def version_matches_requirements?(version, requirements)
    return true if requirements.blank? || requirements == "*"
    
    SemanticRange.satisfies?(version.clean_number, requirements)
  rescue ArgumentError
    version.clean_number == requirements.to_s
  end

  def merge_duplicate_dependencies(dependencies)
    grouped = dependencies.group_by(&:package_name)
    
    grouped.map do |package_name, deps|
      if deps.length == 1
        deps.first
      else
        merged_requirements = merge_requirements(deps.map(&:requirements))
        deps.first.dup.tap { |dep| dep.requirements = merged_requirements }
      end
    end
  end

  def merge_requirements(requirements_array)
    requirements_array.join(" ")
  end

  def build_cache_key
    options_hash = Digest::MD5.hexdigest([
      @include_optional,
      @kind,
      @max_dependencies
    ].to_json)
    
    "transitive_deps:#{@registry.id}:#{@package.name}:#{@version.number}:#{@max_depth}:#{options_hash}"
  end
end