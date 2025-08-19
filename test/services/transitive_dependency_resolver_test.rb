require 'test_helper'

class TransitiveDependencyResolverTest < ActiveSupport::TestCase
  test "resolves direct dependencies only at depth 0" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 0)
    result = resolver.resolve
    
    assert_empty result
  end

  test "resolves single level transitive dependencies" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c = create_version(package_c, "1.0.0")
    
    dep_a_to_b = create_dependency(version_a, package_b.name, "1.0.0")
    dep_b_to_c = create_dependency(version_b, package_c.name, "1.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2)
    result = resolver.resolve
    
    assert_equal 2, result.length
    assert_includes result.map(&:package_name), package_b.name
    assert_includes result.map(&:package_name), package_c.name
  end

  test "prevents circular dependencies" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0")
    create_dependency(version_b, package_a.name, "1.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 5)
    result = resolver.resolve
    
    assert_equal 1, result.length
    assert_equal package_b.name, result.first.package_name
  end

  test "respects max depth limit" do
    registry = create_registry
    packages = []
    versions = []
    
    5.times do |i|
      packages[i] = create_package(registry, "package-#{i}")
      versions[i] = create_version(packages[i], "1.0.0")
    end
    
    4.times do |i|
      create_dependency(versions[i], packages[i + 1].name, "1.0.0")
    end
    
    resolver = TransitiveDependencyResolver.new(versions[0], max_depth: 3)
    result = resolver.resolve
    
    assert_equal 3, result.length
  end

  test "skips missing packages gracefully" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    create_dependency(version_a, "missing-package", "1.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2)
    result = resolver.resolve
    
    assert_empty result
  end

  test "filters by dependency kind" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c = create_version(package_c, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0", kind: "runtime")
    create_dependency(version_a, package_c.name, "1.0.0", kind: "dev")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2, kind: "runtime")
    result = resolver.resolve
    
    assert_equal 1, result.length
    assert_equal package_b.name, result.first.package_name
  end

  test "filters optional dependencies" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c = create_version(package_c, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0", optional: false)
    create_dependency(version_a, package_c.name, "1.0.0", optional: true)
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2, include_optional: false)
    result = resolver.resolve
    
    assert_equal 1, result.length
    assert_equal package_b.name, result.first.package_name
  end

  test "includes optional dependencies when requested" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c = create_version(package_c, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0", optional: false)
    create_dependency(version_a, package_c.name, "1.0.0", optional: true)
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2, include_optional: true)
    result = resolver.resolve
    
    assert_equal 2, result.length
    package_names = result.map(&:package_name)
    assert_includes package_names, package_b.name
    assert_includes package_names, package_c.name
  end

  test "caches results" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0")
    
    resolver1 = TransitiveDependencyResolver.new(version_a, max_depth: 2)
    result1 = resolver1.resolve
    
    resolver2 = TransitiveDependencyResolver.new(version_a, max_depth: 2)
    
    Rails.cache.expects(:fetch).once.returns(result1)
    result2 = resolver2.resolve
    
    assert_equal result1, result2
  end

  test "merges requirements for same package appearing multiple times" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c = create_version(package_c, "1.0.0")
    
    package_d = create_package(registry, "package-d")
    version_d = create_version(package_d, "1.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0")
    create_dependency(version_a, package_c.name, "1.0.0")
    create_dependency(version_b, package_d.name, ">=1.0.0")
    create_dependency(version_c, package_d.name, ">=1.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 3)
    result = resolver.resolve
    
    package_d_deps = result.select { |dep| dep.package_name == package_d.name }
    assert_equal 1, package_d_deps.length
    assert_equal ">=1.0.0 || >=1.0.0", package_d_deps.first.requirements
  end

  test "raises error when no version satisfies requirements" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    create_dependency(version_a, package_b.name, ">=2.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2)
    
    error = assert_raises(TransitiveDependencyResolver::DependencyResolutionError) do
      resolver.resolve
    end
    
    assert_includes error.message, "No version of 'package-b' satisfies requirements: >=2.0.0"
  end

  test "raises error when too many dependencies exceed limit" do
    registry = create_registry
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c = create_version(package_c, "1.0.0")
    
    # Create 3 direct dependencies from package-a
    create_dependency(version_a, package_b.name, "1.0.0")
    create_dependency(version_a, package_c.name, "1.0.0")
    create_dependency(version_a, "package-d", "1.0.0") # This one won't be found, so only 2 dependencies
    
    # Add one more real dependency to exceed the limit
    package_e = create_package(registry, "package-e")
    version_e = create_version(package_e, "1.0.0")
    create_dependency(version_a, package_e.name, "1.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2, max_dependencies: 2)
    
    error = assert_raises(TransitiveDependencyResolver::DependencyResolutionError) do
      resolver.resolve
    end
    
    assert_includes error.message, "Too many dependencies: 3 exceeds limit of 2"
  end

  test "allows multiple versions for npm and cargo ecosystems" do
    registry = create_registry("npm")
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    package_b = create_package(registry, "package-b")
    version_b = create_version(package_b, "1.0.0")
    
    package_c = create_package(registry, "package-c")
    version_c_1 = create_version(package_c, "1.0.0")
    version_c_2 = create_version(package_c, "2.0.0")
    
    create_dependency(version_a, package_b.name, "1.0.0")
    create_dependency(version_a, package_c.name, "1.0.0")
    create_dependency(version_b, package_c.name, "2.0.0")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 3)
    result = resolver.resolve
    
    package_c_deps = result.select { |dep| dep.package_name == package_c.name }
    assert_equal 2, package_c_deps.length
    assert_includes package_c_deps.map(&:requirements), "1.0.0"
    assert_includes package_c_deps.map(&:requirements), "2.0.0"
  end

  test "handles activesupport-like version matching" do
    registry = create_registry("rubygems")
    package_a = create_package(registry, "package-a")
    version_a = create_version(package_a, "1.0.0")
    
    activesupport = create_package(registry, "activesupport")
    create_version(activesupport, "8.0.2.1")
    create_version(activesupport, "8.0.2")
    create_version(activesupport, "8.0.1")
    create_version(activesupport, "8.0.0.rc2")
    create_version(activesupport, "8.0.0.rc1")
    
    create_dependency(version_a, activesupport.name, ">= 5.2.4.5")
    
    resolver = TransitiveDependencyResolver.new(version_a, max_depth: 2)
    result = resolver.resolve
    
    assert_equal 1, result.length
    assert_equal "activesupport", result.first.package_name
    assert_equal ">= 5.2.4.5", result.first.requirements
  end

  private

  def create_registry(ecosystem = "test")
    Registry.create!(
      name: "test-registry",
      url: "https://test.example.com",
      ecosystem: ecosystem
    )
  end

  def create_package(registry, name)
    Package.create!(
      registry: registry,
      name: name,
      ecosystem: registry.ecosystem
    )
  end

  def create_version(package, number)
    Version.create!(
      package: package,
      number: number,
      registry: package.registry
    )
  end

  def create_dependency(version, package_name, requirements, kind: "runtime", optional: false)
    Dependency.create!(
      version: version,
      package_name: package_name,
      requirements: requirements,
      kind: kind,
      optional: optional,
      ecosystem: version.package.ecosystem
    )
  end
end