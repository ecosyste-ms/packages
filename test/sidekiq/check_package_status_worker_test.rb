require "test_helper"

class CheckPackageStatusWorkerTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @package = @registry.packages.create!(name: 'foo', ecosystem: 'rubygems')
  end

  test "perform calls Package#check_status" do
    Package.any_instance.expects(:check_status)
    CheckPackageStatusWorker.new.perform(@registry.id, @package.id)
  end

  test "perform is a no-op for missing package" do
    assert_nothing_raised do
      CheckPackageStatusWorker.new.perform(@registry.id, 0)
    end
  end

  test "check_status_async enqueues CheckPackageStatusWorker with registry_id and package_id" do
    CheckPackageStatusWorker.expects(:perform_async).with(@registry.id, @package.id)
    @package.check_status_async
  end

  test "shares the registry_host throttle strategy" do
    assert_same Sidekiq::Throttled::Registry.get(:registry_host),
                Sidekiq::Throttled::Registry.get('CheckPackageStatusWorker')
  end
end
