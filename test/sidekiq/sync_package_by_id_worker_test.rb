require "test_helper"

class SyncPackageByIdWorkerTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @package = @registry.packages.create!(name: 'foo', ecosystem: 'rubygems')
  end

  test "perform calls Package#sync" do
    Package.any_instance.expects(:sync)
    SyncPackageByIdWorker.new.perform(@registry.id, @package.id)
  end

  test "perform is a no-op for missing package" do
    assert_nothing_raised { SyncPackageByIdWorker.new.perform(@registry.id, 0) }
  end

  test "sync_async enqueues SyncPackageByIdWorker with registry_id and package_id" do
    Registry.any_instance.stubs(:sync_in_batches?).returns(false)
    SyncPackageByIdWorker.expects(:perform_async).with(@registry.id, @package.id)
    @package.sync_async
  end

  test "shares the registry_host throttle strategy" do
    assert_same Sidekiq::Throttled::Registry.get(:registry_host),
                Sidekiq::Throttled::Registry.get('SyncPackageByIdWorker')
  end
end
