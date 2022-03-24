require "test_helper"

class SyncPackageWorkerTest < ActiveSupport::TestCase
  test 'perform' do
    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @registry.expects(:sync_package).with('foo')
    Registry.expects(:find_by_id).with(@registry.id).returns(@registry)
    job = SyncPackageWorker.new
    job.perform(@registry.id, 'foo')
  end
end