require "test_helper"

class SyncPackageVersionWorkerTest < ActiveSupport::TestCase
  test 'lock_args ignores the indexed version' do
    assert_equal [5, 'example.com/module'], SyncPackageVersionWorker.lock_args([5, 'example.com/module', 'v1.2.3'])
  end

  test 'perform syncs a missing package with its indexed version' do
    registry = Registry.create!(name: 'Go modules', url: 'https://go.example', ecosystem: 'Go')
    registry.expects(:sync_package).with('example.com/module', version: 'v1.2.3')
    Registry.expects(:find_by_id).with(registry.id).returns(registry)

    SyncPackageVersionWorker.new.perform(registry.id, 'example.com/module', 'v1.2.3')
  end

  test 'perform skips a package created after discovery' do
    registry = Registry.create!(name: 'Go modules', url: 'https://go.example', ecosystem: 'Go')
    registry.packages.create!(name: 'example.com/module', ecosystem: 'go')
    registry.expects(:sync_package).never

    SyncPackageVersionWorker.new.perform(registry.id, 'example.com/module', 'v1.2.3')
  end
end
