require "test_helper"

class SyncPackageVersionWorkerTest < ActiveSupport::TestCase
  test 'perform syncs a missing package with its indexed version' do
    registry = Registry.create!(name: 'Go modules', url: 'https://go.example', ecosystem: 'Go')
    registry.expects(:sync_package).with('example.com/module', force: false, version: 'v1.2.3')
    Registry.expects(:find_by_id).with(registry.id).returns(registry)

    SyncPackageVersionWorker.new.perform(registry.id, 'example.com/module', 'v1.2.3')
  end

  test 'perform syncs a missing version when the package was created after discovery' do
    registry = Registry.create!(name: 'Go modules', url: 'https://go.example', ecosystem: 'Go')
    registry.packages.create!(name: 'example.com/module', ecosystem: 'go')
    registry.expects(:sync_package).with('example.com/module', force: true, version: 'v1.2.3')
    Registry.expects(:find_by_id).with(registry.id).returns(registry)

    SyncPackageVersionWorker.new.perform(registry.id, 'example.com/module', 'v1.2.3')
  end

  test 'perform skips an indexed version that already exists' do
    registry = Registry.create!(name: 'Go modules', url: 'https://go.example', ecosystem: 'Go')
    package = registry.packages.create!(name: 'example.com/module', ecosystem: 'go')
    package.versions.create!(number: 'v1.2.3', registry: registry)
    registry.expects(:sync_package).never

    SyncPackageVersionWorker.new.perform(registry.id, 'example.com/module', 'v1.2.3')
  end
end
