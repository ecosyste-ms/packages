require 'test_helper'
require 'rake'

class PackagesRakeTest < ActiveSupport::TestCase
  setup do
    # Only load tasks if they haven't been loaded yet, and suppress stats warning
    if Rake::Task.tasks.empty?
      # Suppress the STATS_DIRECTORIES redefinition warning when loading tasks in tests
      silence_warnings do
        Packages::Application.load_tasks
      end
    end
  end

  test "should sync recent packages" do
    Registry.expects(:sync_all_recently_updated_packages_async).returns(:true)
    Rake::Task["packages:sync_recent"].invoke
  end

  test "should sync all packages" do
    Registry.expects(:sync_all_packages).returns(:true)
    Rake::Task["packages:sync_all"].invoke
  end

  test "should sync least recently synced packages" do
    Package.expects(:sync_least_recent_async).returns(:true)
    Rake::Task["packages:sync_least_recent"].invoke
  end

  test "nixpkgs_python_native_deps reports non-python dependencies" do
    registry = Registry.create(name: 'Nixpkgs', url: 'https://search.nixos.org', ecosystem: 'nixpkgs', packages_count: 3)

    numpy = Package.create(name: 'python311Packages.numpy', ecosystem: 'nixpkgs', registry: registry,
                           metadata: { 'upstream_ecosystem' => 'pypi' })
    version = Version.create(package: numpy, number: '1.26.4', registry: registry)
    Dependency.create(version: version, package_name: 'blas', ecosystem: 'nixpkgs', requirements: '*', kind: 'runtime')
    Dependency.create(version: version, package_name: 'pytest', ecosystem: 'nixpkgs', requirements: '*', kind: 'test')

    Package.create(name: 'python311Packages.pytest', ecosystem: 'nixpkgs', registry: registry,
                   metadata: { 'upstream_ecosystem' => 'pypi' })

    output = capture_io { Rake::Task["packages:nixpkgs_python_native_deps"].invoke }.first

    assert_match(/blas,1,numpy/, output)
    assert_no_match(/pytest/, output)
  end

  test "nixpkgs_upstream_ecosystems reports ecosystem groupings" do
    registry = Registry.create(name: 'Nixpkgs', url: 'https://search.nixos.org', ecosystem: 'nixpkgs', packages_count: 3)

    Package.create(name: 'python311Packages.requests', ecosystem: 'nixpkgs', registry: registry,
                   metadata: { 'upstream_ecosystem' => 'pypi', 'upstream_name' => 'requests' })
    Package.create(name: 'python311Packages.numpy', ecosystem: 'nixpkgs', registry: registry,
                   metadata: { 'upstream_ecosystem' => 'pypi', 'upstream_name' => 'numpy' })
    Package.create(name: 'openssl', ecosystem: 'nixpkgs', registry: registry,
                   metadata: {})

    output = capture_io { Rake::Task["packages:nixpkgs_upstream_ecosystems"].invoke }.first

    assert_match(/pypi: 2/, output)
    assert_match(/\(none\): 1/, output)
    assert_match(/Total with upstream mapping: 2/, output)
    assert_match(/Total without: 1/, output)
  end
end