require 'test_helper'

class PackagistSnapshotTest < ActiveSupport::TestCase
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    @time = Time.current.change(usec: 0)
    @registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @package = @registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', status: 'active')
    @url = 'https://repo.packagist.org/p2/psr/log.json'
    @key = ['packagist', 'tagged_versions', 'psr/log']
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(body: file_fixture('packagist/log.json.1'))
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(body: {packages: {'psr/log' => [{version: 'dev-master'}]}}.to_json)
  end

  %w[sync versions].product(%w[sync versions]).each do |older_path, newer_path|
    test "#{older_path} rejects an older in-flight snapshot after #{newer_path} imports a newer release" do
      newer_state = nil
      stub_request(:get, @url).to_return do
        stub_request(:get, @url).to_return(snapshot(%w[2.0.0 1.0.0], @time))
        perform(newer_path)
        newer_state = persisted_state
        snapshot(['1.0.0'], @time - 1.hour)
      end

      error = assert_raises(Ecosystem::Packagist::RetryableError) { perform(older_path) }

      assert_includes error.message, 'last applied snapshot'
      assert_equal newer_state, persisted_state
      assert_equal '2.0.0', @package.reload.latest_release_number
      assert_equal @time.to_i, @package.metadata['packagist_snapshot']['last_modified']
      assert_equal @time.httpdate, Rails.cache.read(@key)['last_modified']
      stub_request(:get, @url).with(headers: {'If-Modified-Since' => @time.httpdate}).to_return(status: 304)
      perform(older_path)
      assert_equal '2.0.0', @package.reload.latest_release_number
      assert_equal %w[1.0.0 2.0.0], @package.versions.active.order(:number).pluck(:number)
    end
  end

  %w[sync versions].each do |path|
    test "#{path} rejects a stale cached 304 after another worker advances the snapshot" do
      stub_request(:get, @url).to_return(snapshot(['1.0.0'], @time - 1.hour))
      perform(path)
      newer_state = nil
      stub_request(:get, @url).to_return do
        stub_request(:get, @url).to_return(snapshot(%w[2.0.0 1.0.0], @time))
        perform('sync')
        newer_state = persisted_state
        {status: 304}
      end

      assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }

      assert_equal newer_state, persisted_state
      assert_equal @time.httpdate, Rails.cache.read(@key)['last_modified']
    end

    test "#{path} invalidates an older cached body without losing the applied checkpoint" do
      stub_request(:get, @url).to_return(snapshot(%w[2.0.0 1.0.0], @time))
      perform(path)
      previous = persisted_state
      old = snapshot(['1.0.0'], @time - 1.hour)
      Rails.cache.write(@key, {'body' => old[:body], 'last_modified' => old[:headers]['Last-Modified']})
      stub_request(:get, @url).to_return(status: 304)

      assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }

      assert_equal previous, persisted_state
      assert_nil Rails.cache.read(@key)
    end

    test "#{path} rejects conflicting content at the same timestamp and accepts a later snapshot" do
      stub_request(:get, @url).to_return(snapshot(%w[2.0.0 1.0.0], @time))
      perform(path)
      previous = persisted_state
      stub_request(:get, @url).to_return(snapshot(['1.0.0'], @time))

      assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }

      assert_equal previous, persisted_state
      stub_request(:get, @url).to_return(snapshot(['1.0.0'], @time + 1.second))
      perform(path)
      assert_equal 'removed', @package.versions.find_by!(number: '2.0.0').status
      assert_equal '1.0.0', @package.reload.latest_release_number
    end

    test "#{path} refuses untimestamped snapshots before changing records or caching the body" do
      response = snapshot(['1.0.0'], @time).except(:headers)
      stub_request(:get, @url).to_return(response)
      previous = persisted_state

      assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }

      assert_equal previous, persisted_state
      assert_nil Rails.cache.read(@key)
    end
  end

  test 'failed persistence rolls back the checkpoint and leaves the accepted cache intact' do
    stub_request(:get, @url).to_return(snapshot(['1.0.0'], @time))
    perform('sync')
    previous = persisted_state
    cached = Rails.cache.read(@key)
    stub_request(:get, @url).to_return(snapshot(%w[2.0.0 1.0.0], @time + 1.second))
    Version.stubs(:upsert_all).raises(ActiveRecord::StatementInvalid, 'write failed')

    assert_raises(ActiveRecord::StatementInvalid) { perform('sync') }

    assert_equal previous, persisted_state
    assert_equal cached, Rails.cache.read(@key)
    Version.unstub(:upsert_all)
    perform('sync')
    assert_equal '2.0.0', @package.reload.latest_release_number
  end

  def perform(path)
    if path == 'sync'
      SyncPackageWorker.new.perform(@registry.id, 'psr/log', true)
    else
      UpdateVersionsWorker.new.perform(@package.id)
    end
  end

  def persisted_state
    [@package.reload.attributes, @package.versions.order(:id).map(&:attributes)]
  end

  def snapshot(numbers, modified)
    versions = numbers.map { |number| {name: 'psr/log', version: number, time: '2026-11-01T00:00:00Z', require: {php: '>=8.0'}} }
    {body: {packages: {'psr/log' => versions}}.to_json, headers: {'Last-Modified' => modified.httpdate}}
  end
end
