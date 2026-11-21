require 'test_helper'

class SwiftpmDependencyResolutionTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'Swiftpm.io', url: 'https://swiftpm.io', ecosystem: 'swiftpm')
    @target = @registry.packages.create!(name: 'github.com/Alamofire/Alamofire', ecosystem: 'swiftpm', metadata: {'normalized_name' => 'github.com/alamofire/alamofire'})
    @version = @registry.packages.create!(name: 'github.com/example/App', ecosystem: 'swiftpm').versions.create!(number: '1.0.0')
    @dependency = @version.dependencies.create!(package_name: 'github.com/alamofire/alamofire', ecosystem: 'swiftpm', requirements: '5.0.0', kind: 'runtime')
  end

  test 'individual linking matches GitHub case variants' do
    @dependency.update_package_id
    assert_equal @target.id, @dependency.reload.package_id
  end

  test 'batch linking matches GitHub case variants' do
    Dependency.update_missing_package_ids
    assert_equal @target.id, @dependency.reload.package_id
  end

  test 'package linking matches GitHub case variants and updates counts' do
    @target.update_dependent_packages_details
    assert_equal @target.id, @dependency.reload.package_id
    assert_equal 1, @target.reload.dependent_packages_count
  end

  test 'case insensitive lookups stay within the owning registry' do
    other = Registry.create!(name: 'Other Swift', url: 'https://swift.example.org', ecosystem: 'swiftpm')
    external = other.packages.create!(name: @dependency.package_name, ecosystem: 'swiftpm')
    external.update_dependent_package_ids
    assert_nil @dependency.reload.package_id
    Dependency.update_missing_package_ids
    assert_equal @target.id, @dependency.reload.package_id
  end

  test 'case insensitive linking leaves existing links untouched' do
    existing = @registry.packages.create!(name: 'github.com/other/Library', ecosystem: 'swiftpm')
    @dependency.update!(package_id: existing.id)
    @dependency.update_package_id
    Dependency.update_missing_package_ids
    @target.update_dependent_package_ids
    assert_equal existing.id, @dependency.reload.package_id
  end

  test 'ambiguous case variants require an exact match' do
    duplicate = @registry.packages.create!(name: 'github.com/alamofire/ALAMOFIRE', ecosystem: 'swiftpm', metadata: @target.metadata)
    @dependency.update_package_id
    Dependency.update_missing_package_ids
    @target.update_dependent_package_ids
    duplicate.update_dependent_package_ids
    assert_nil @dependency.reload.package_id

    @dependency.update!(package_name: duplicate.name)
    @target.update_dependent_package_ids
    assert_nil @dependency.reload.package_id
    @dependency.update_package_id
    assert_equal duplicate.id, @dependency.reload.package_id
  end

  test 'other Swift hosts retain case sensitive names' do
    @target.update!(name: 'gitlab.com/Example/Library')
    @dependency.update!(package_name: 'gitlab.com/example/library')
    @dependency.update_package_id
    Dependency.update_missing_package_ids
    @target.update_dependent_package_ids
    assert_nil @dependency.reload.package_id
  end

  test 'other ecosystems retain case sensitive names' do
    @registry.update!(ecosystem: 'carthage')
    @target.update!(ecosystem: 'carthage')
    @dependency.update!(ecosystem: 'carthage')
    @dependency.update_package_id
    Dependency.update_missing_package_ids
    @target.update_dependent_package_ids
    assert_nil @dependency.reload.package_id
  end
end
