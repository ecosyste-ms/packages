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
    @visited_packages = {}
    @package_cache = {}
    @version_cache = {}
    @satisfies_cache = {}
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
    return [] if @visited_packages[package_key]
    
    @visited_packages[package_key] = true
    
    direct_dependencies = get_filtered_dependencies(version)
    all_dependencies = []
    
    direct_dependencies.each do |dependency|
      dependency_package = find_dependency_package(dependency)
      next unless dependency_package
      
      matching_version = find_matching_version(dependency_package, dependency.requirements)
      next unless matching_version
      
      dependency_package_key = "#{matching_version.package.name}:#{matching_version.number}"
      next if @visited_packages[dependency_package_key]
      
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
    @package_cache[dependency.package_name] ||= @registry.packages.includes(:versions).find_by(name: dependency.package_name)
  end

  def find_matching_version(package, requirements)
    cache_key = "#{package.name}:#{requirements}"
    
    @version_cache[cache_key] ||= begin
      normalized_requirements = normalize_version_requirements(requirements)
      
      matching_versions = package.versions.select do |version|
        version_matches_requirements?(version, normalized_requirements)
      end
      
      if matching_versions.empty?
        available_versions = package.versions.map(&:clean_number).sort.reverse.first(5)
        Rails.logger.debug "Available versions for #{package.name}: #{available_versions.join(', ')}"
        
        raise DependencyResolutionError.new(
          "No version of '#{package.name}' satisfies requirements: #{requirements}. Available versions: #{available_versions.join(', ')}"
        )
      end
      
      select_best_version(matching_versions)
    end
  end

  def select_best_version(matching_versions)
    matching_versions.sort.first
  end

  def normalize_version_requirements(requirements)
    requirements.to_s
  end

  def version_matches_requirements?(version, requirements)
    return true if requirements.blank? || requirements == "*"
    
    cache_key = "#{version.clean_number}:#{requirements}"
    @satisfies_cache[cache_key] ||= begin
      require 'vers'
      
      Vers.satisfies?(version.clean_number, requirements, vers_platform)
    rescue
      # Fallback to string comparison if vers fails
      version.clean_number == requirements.to_s
    end
  end

  def vers_platform
    case @registry.ecosystem
    when 'rubygems'
      'gem'
    when 'packagist'
      'composer'
    when 'npm'
      'npm'
    when 'cargo'
      'cargo'
    else
      raise ArgumentError, "Unsupported ecosystem for version resolution: #{@registry.ecosystem}"
    end
  end

  def merge_duplicate_dependencies(dependencies)
    if allows_multiple_versions?
      dependencies.uniq { |dep| "#{dep.package_name}:#{resolved_version_for(dep)}" }
    else
      result = []
      seen = {}
      
      dependencies.each do |dep|
        if existing = seen[dep.package_name]
          existing.requirements = merge_requirements([existing.requirements, dep.requirements])
        else
          seen[dep.package_name] = dep
          result << dep
        end
      end
      
      result
    end
  end

  def allows_multiple_versions?
    %w[cargo npm].include?(@registry.ecosystem)
  end

  def resolved_version_for(dependency)
    dependency_package = find_dependency_package(dependency)
    return dependency.requirements unless dependency_package
    
    matching_version = find_matching_version(dependency_package, dependency.requirements)
    matching_version&.number || dependency.requirements
  end

  def merge_requirements(requirements_array)
    requirements_array.uniq.join(", ")
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