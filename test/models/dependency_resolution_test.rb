require 'test_helper'

class DependencyResolutionTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

  setup do
    @source = Registry.create!(name: 'maven.google.com', url: 'https://maven.google.com', ecosystem: 'maven')
    @other = Registry.create!(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven')
    @source_library = @source.packages.create!(name: 'com.example:library', ecosystem: 'maven')
    @other_library = @other.packages.create!(name: @source_library.name, ecosystem: 'maven')
    @source_version = @source.packages.create!(name: 'com.example:consumer', ecosystem: 'maven').versions.create!(number: '1.0.0')
    @other_version = @other.packages.create!(name: 'com.example:consumer', ecosystem: 'maven').versions.create!(number: '1.0.0')
    @other.update_column(:packages_count, 1_000_000)
  end

  test 'instance lookup resolves the same name independently in each owning registry' do
    assert_equal @source_library.id, create_dependency(@source_version).find_package_id
    assert_equal @other_library.id, create_dependency(@other_version).find_package_id
  end

  test 'instance lookup uses the package registry rather than the optional version registry' do
    assert_nil @source_version.registry_id
    dependency = create_dependency(@source_version)
    assert_equal @source_library.id, dependency.find_package_id

    @source_version.update_column(:registry_id, @other.id)
    assert_equal @source_library.id, dependency.reload.find_package_id
  end

  test 'instance lookup leaves a package found only in another registry unresolved' do
    @other.packages.create!(name: 'com.example:external', ecosystem: 'maven')
    dependency = create_dependency(@source_version, package_name: 'com.example:external')

    assert_nil dependency.find_package_id
    dependency.update_package_id
    assert_nil dependency.reload.package_id
  end

  test 'instance lookup without an owning version does not guess a registry' do
    dependency = Dependency.new(package_name: @source_library.name, ecosystem: 'maven', requirements: '*')

    assert_nil dependency.find_package_id
  end

  test 'instance lookup does not link a different dependency ecosystem' do
    npm = Registry.create!(name: 'npm.example', url: 'https://npm.example', ecosystem: 'npm')
    npm.packages.create!(name: @source_library.name, ecosystem: 'npm')
    dependency = create_dependency(@source_version, ecosystem: 'npm')

    assert_nil dependency.find_package_id
    dependency.update_package_id
    assert_nil dependency.reload.package_id
  end

  test 'instance update links a local match without overwriting an existing link' do
    dependency = create_dependency(@source_version)
    dependency.update_package_id
    assert_equal @source_library.id, dependency.reload.package_id

    dependency.update_column(:package_id, @other_library.id)
    dependency.update_package_id
    assert_equal @other_library.id, dependency.reload.package_id
  end

  test 'bulk backfill scopes the same dependency name to each owning registry' do
    source_dependency = create_dependency(@source_version)
    other_dependency = create_dependency(@other_version)

    Dependency.update_missing_package_ids

    assert_equal @source_library.id, source_dependency.reload.package_id
    assert_equal @other_library.id, other_dependency.reload.package_id
  end

  test 'bulk backfill isolates missing matches from matches in other registries' do
    @other.packages.create!(name: 'com.example:external', ecosystem: 'maven')
    missing = create_dependency(@source_version, package_name: 'com.example:external')
    match = create_dependency(@other_version, package_name: 'com.example:external')

    Dependency.update_missing_package_ids

    assert_nil missing.reload.package_id
    assert_equal @other.packages.find_by!(name: 'com.example:external').id, match.reload.package_id
  end

  test 'bulk cache separates dependency ecosystems for the same owner and name' do
    match = create_dependency(@source_version)
    mismatch = create_dependency(@source_version, ecosystem: 'npm')

    Dependency.update_missing_package_ids

    assert_equal @source_library.id, match.reload.package_id
    assert_nil mismatch.reload.package_id
  end

  test 'bulk backfill leaves existing links untouched' do
    dependency = create_dependency(@source_version, package_id: @other_library.id)

    Dependency.update_missing_package_ids

    assert_equal @other_library.id, dependency.reload.package_id
  end

  test 'bulk backfill caches missing lookups across batches and preloads owner context' do
    Dependency.insert_all(Array.new(1001) do
      { version_id: @source_version.id, package_name: 'com.example:missing', ecosystem: 'maven', requirements: '*' }
    end)

    assert_queries_match(/\ASELECT .* FROM "packages".*"packages"\."name"/, count: 1) do
      Dependency.strict_loading.update_missing_package_ids
    end

    assert_equal 1001, Dependency.without_package.count
  end

  test 'bulk backfill caches successful lookups and preloads owner context' do
    dependencies = Array.new(3) { create_dependency(@source_version) }

    assert_queries_match(/\ASELECT .* FROM "packages".*"packages"\."name"/, count: 1) do
      Dependency.strict_loading.update_missing_package_ids
    end

    assert_equal [@source_library.id], dependencies.map { |dependency| dependency.reload.package_id }.uniq
  end

  test 'package driven backfill links only dependencies from its own registry' do
    source_dependency = create_dependency(@source_version)
    other_dependency = create_dependency(@other_version)

    @other_library.update_dependent_package_ids

    assert_nil source_dependency.reload.package_id
    assert_equal @other_library.id, other_dependency.reload.package_id

    @source_library.update_dependent_package_ids

    assert_equal @source_library.id, source_dependency.reload.package_id
    assert_equal @other_library.id, other_dependency.reload.package_id
  end

  test 'package driven backfill does not guess a cross-registry match' do
    external = @other.packages.create!(name: 'com.example:external', ecosystem: 'maven')
    dependency = create_dependency(@source_version, package_name: external.name)

    external.update_dependent_package_ids

    assert_nil dependency.reload.package_id
  end

  test 'package driven backfill preserves existing links and dependency ecosystem filters' do
    existing = create_dependency(@source_version, package_id: @other_library.id)
    mismatch = create_dependency(@source_version, ecosystem: 'npm')
    missing = create_dependency(@source_version, package_name: 'com.example:missing')

    @source_library.update_dependent_package_ids

    assert_equal @other_library.id, existing.reload.package_id
    assert_nil mismatch.reload.package_id
    assert_nil missing.reload.package_id
  end

  def create_dependency(version, **attributes)
    version.dependencies.create!({ package_name: @source_library.name, ecosystem: 'maven', requirements: '*' }.merge(attributes))
  end
end
