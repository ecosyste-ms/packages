require "test_helper"

class RegistryTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:packages)
    should have_many(:versions)
  end

  context 'validations' do
    should validate_presence_of(:url)
    should validate_presence_of(:name)
    should validate_presence_of(:ecosystem)
    should validate_uniqueness_of(:name)
    should validate_uniqueness_of(:url)
  end

  setup do
    @registry = Registry.new(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
  end

  test 'list_all_package_names' do
    ecosystem = @registry.ecosystem_instance
    ecosystem.expects(:all_package_names).returns(['rails', 'split', 'mocha'])
    all_package_names = @registry.all_package_names
    assert_equal all_package_names, ['rails', 'split', 'mocha']
  end

  test 'recently_updated_package_names' do
    ecosystem = @registry.ecosystem_instance
    ecosystem.expects(:recently_updated_package_names).returns(['oj', 'rake', 'json'])
    recently_updated_package_names = @registry.recently_updated_package_names
    assert_equal recently_updated_package_names, ['oj', 'rake', 'json']
  end

  test 'missing_package_names' do
    skip("To be implemented")
  end

  test 'existing_package_names' do
    skip("To be implemented")
  end

  test 'sync_all_packages' do
    skip("To be implemented")
  end
  
  test 'sync_missing_packages' do
    skip("To be implemented")
  end
  
  test 'sync_recently_updated_packages' do
    skip("To be implemented")
  end
  
  test 'sync_package' do
    skip("To be implemented")
  end

  test 'sync_package_async' do
    skip("test bug: unique job queue not being cleared properly")
    assert_equal 0, SyncPackageWorker.jobs.size
    @registry.sync_package_async('split')
    assert_equal 1, SyncPackageWorker.jobs.size
  end
end
