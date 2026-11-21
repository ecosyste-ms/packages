require 'test_helper'

class SyncClojarsReleaseWorkerTest < ActiveSupport::TestCase
  test 'release jobs force a fresh Clojars package sync' do
    registry = Registry.create!(name: 'Clojars worker', url: 'https://clojars-worker.example', ecosystem: 'clojars')
    Registry.any_instance.expects(:sync_package).with('missionary', force: true)

    SyncClojarsReleaseWorker.new.perform(registry.id, 'missionary')
  end

  test 'release jobs ignore missing and non-Clojars registries' do
    registry = Registry.create!(name: 'Other registry', url: 'https://other-registry.example', ecosystem: 'rubygems')
    Registry.any_instance.expects(:sync_package).never

    SyncClojarsReleaseWorker.new.perform(0, 'missionary')
    SyncClojarsReleaseWorker.new.perform(registry.id, 'missionary')
  end
end
