require 'test_helper'

class CocoapodsDependencyResolutionTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'Cocoapods.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods')
    @target = @registry.packages.create!(name: 'Firebase', ecosystem: 'cocoapods')
    @version = @registry.packages.create!(name: 'SomeApp', ecosystem: 'cocoapods').versions.create!(number: '1.0.0')
    @dependency = @version.dependencies.create!(package_name: 'Firebase/Analytics', ecosystem: 'cocoapods', requirements: '>= 0', kind: 'runtime')
  end

  test 'individual linking resolves cocoapods subspecs without rewriting their names' do
    @dependency.update_package_id
    assert_equal @target.id, @dependency.reload.package_id
    assert_equal 'Firebase/Analytics', @dependency.reload.package_name
  end

  test 'batch linking resolves cocoapods subspecs without rewriting their names' do
    Dependency.update_missing_package_ids
    assert_equal @target.id, @dependency.reload.package_id
    assert_equal 'Firebase/Analytics', @dependency.reload.package_name
  end

  test 'subspec lookups stay within the owning registry' do
    other = Registry.create!(name: 'Other Pods', url: 'https://pods.example.org', ecosystem: 'cocoapods')
    external = other.packages.create!(name: 'Firebase', ecosystem: 'cocoapods')
    external.update_dependent_package_ids
    assert_nil @dependency.reload.package_id
    Dependency.update_missing_package_ids
    assert_equal @target.id, @dependency.reload.package_id
  end
end
