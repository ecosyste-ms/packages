require 'test_helper'
require 'rake'

class RelinkDependenciesRakeTest < ActiveSupport::TestCase
  setup do
    silence_warnings { Rails.application.load_tasks } unless Rake::Task.task_defined?('packages:relink_dependencies')
    @registry = Registry.create!(name: 'PyPI.org', url: 'https://pypi.org', ecosystem: 'pypi')
    @target = @registry.packages.create!(name: 'cryptography', ecosystem: 'pypi')
    @version = @registry.packages.create!(name: 'consumer', ecosystem: 'pypi').versions.create!(number: '1.0.0')
    UpdateDependentPackagesCountWorker.clear
  end

  test 'repair advances across other registries and links one bounded batch before recounting' do
    other = Registry.create!(name: 'mirror', url: 'https://mirror.example', ecosystem: 'pypi')
    other_version = other.packages.create!(name: 'consumer', ecosystem: 'pypi').versions.create!(number: '1.0.0')
    foreign = dependency(other_version)
    local = dependency(@version)
    later = dependency(@version)
    existing = dependency(@version, package_id: @target.id)
    mismatch = dependency(@version, ecosystem: 'npm')

    first = invoke_repair(after_id: 0, batch_size: 1)
    assert_equal({ 'cursor' => foreign.id, 'scanned' => 1, 'linked' => 0 }, first)
    assert_empty UpdateDependentPackagesCountWorker.jobs
    second = invoke_repair(after_id: first['cursor'], batch_size: 1)
    assert_equal({ 'cursor' => local.id, 'scanned' => 1, 'linked' => 1 }, second)
    assert_equal @target.id, local.reload.package_id
    assert_nil foreign.reload.package_id
    assert_nil later.reload.package_id
    assert_nil mismatch.reload.package_id
    assert_equal @target.id, existing.reload.package_id
    assert_equal [[@target.id]], UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'] }

    third = invoke_repair(after_id: second['cursor'], batch_size: 1)
    assert_equal 1, third['linked']
    assert_equal({ 'cursor' => later.id, 'scanned' => 0, 'linked' => 0 }, invoke_repair(after_id: third['cursor'], batch_size: 1))
    UpdateDependentPackagesCountWorker.drain
    assert_equal 1, @target.reload.dependent_packages_count
  end

  test 'repair leaves missing targets and orphaned versions unresolved and returns a cursor' do
    @target.delete
    missing = dependency(@version)
    orphan = dependency(@version, version_id: -1)
    result = invoke_repair(after_id: 0, batch_size: 1000)
    assert_equal({ 'cursor' => orphan.id, 'scanned' => 2, 'linked' => 0 }, result)
    assert_nil missing.reload.package_id
    assert_nil orphan.reload.package_id
    assert_empty UpdateDependentPackagesCountWorker.jobs
  end

  test 'repair rejects invalid bounds before writing' do
    assert_raises(ArgumentError) { invoke_repair(after_id: -1, batch_size: 1) }
    assert_raises(ArgumentError) { invoke_repair(after_id: 0, batch_size: 1001) }
    assert_raises(ArgumentError) { invoke_repair(after_id: 0, batch_size: 0) }
  end

  def dependency(version, **attributes)
    version.dependencies.create!({ package_name: 'Cryptography', ecosystem: 'pypi', requirements: '*' }.merge(attributes))
  end

  def invoke_repair(after_id:, batch_size:)
    task = Rake::Task['packages:relink_dependencies']
    task.reenable
    output, = capture_io { task.invoke('pypi.org', 'Cryptography', after_id, batch_size) }
    JSON.parse(output)
  end
end
