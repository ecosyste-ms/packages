require "test_helper"

class ReleaseSyncTest < ActiveSupport::TestCase
  setup do
    SyncPackageWorker.clear
    @registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @published_at = 1.hour.ago.change(usec: 0)
    @package = @registry.packages.create!(name: 'lazy_static', ecosystem: 'cargo', last_synced_at: 2.hours.ago,
      latest_release_number: '1.5.0', latest_release_published_at: 1.year.ago)
    @package.versions.create!(number: '1.5.0', published_at: 1.year.ago, latest: true)
    @metadata = {
      crate: { id: 'lazy_static', keywords: [], downloads: 100 },
      versions: [
        { num: '1.5.1', created_at: @published_at.iso8601, yanked: false, license: 'MIT' },
        { num: '1.5.0', created_at: 1.year.ago.iso8601, yanked: false, license: 'MIT' }
      ]
    }
    stub_request(:get, 'https://crates.io/api/v1/crates/lazy_static')
      .to_return(status: 200, body: @metadata.to_json, headers: { content_type: 'application/json' })
    stub_request(:get, %r{https://crates.io/api/v1/crates/lazy_static/1\.5\.[01]/dependencies})
      .to_return(status: 200, body: { dependencies: [] }.to_json, headers: { content_type: 'application/json' })
  end

  teardown do
    SyncPackageWorker.clear
  end

  test 'recent update polling imports a release within a day of the previous sync' do
    @registry.packages.create!(name: 'recently_synced', ecosystem: 'cargo', last_synced_at: 5.minutes.ago)
    stub_request(:get, 'https://crates.io/api/v1/summary')
      .to_return(status: 200, body: { just_updated: [{ name: 'lazy_static' }, { name: 'recently_synced' }], new_crates: [] }.to_json)

    Registry.sync_all_recently_updated_packages_async

    assert_equal 1, SyncPackageWorker.jobs.size
    args = SyncPackageWorker.jobs.first['args']
    assert_equal [@registry.id, 'lazy_static'], args.first(2)
    UpdateDetailsWorker.expects(:perform_async).never
    SyncPackageWorker.new.perform(*args)

    assert_latest_release '1.5.1', @published_at
    assert_equal 2, @package.versions_count
    assert_operator @package.last_synced_at, :>, 1.minute.ago
  end

  test 'ordinary syncs still defer packages synced within a day' do
    SyncPackageWorker.new.perform(@registry.id, @package.name)

    assert_equal ['1.5.0'], @package.versions.pluck(:number)
    assert_equal '1.5.0', @package.reload.latest_release_number
    assert_equal 1, SyncPackageWorker.jobs.size
    assert_in_delta @package.last_synced_at.to_f + 1.day, SyncPackageWorker.jobs.first['at'], 1
  end

  test 'version update worker refreshes latest fields after importing a release' do
    UpdateDetailsWorker.expects(:perform_async).never

    UpdateVersionsWorker.new.perform(@package.id)

    assert_latest_release '1.5.1', @published_at
    assert_equal 2, @package.versions_count
    assert_not_nil @package.versions_updated_at
  end

  test 'version update worker replaces a latest release that has been yanked' do
    @package.versions.update_all(latest: false)
    @package.versions.create!(number: '1.5.1', published_at: @published_at, latest: true)
    @package.update!(latest_release_number: '1.5.1', latest_release_published_at: @published_at)
    @metadata[:versions].first[:yanked] = true
    stub_request(:get, 'https://crates.io/api/v1/crates/lazy_static')
      .to_return(status: 200, body: @metadata.to_json, headers: { content_type: 'application/json' })

    UpdateVersionsWorker.new.perform(@package.id)

    assert_latest_release '1.5.0', Time.iso8601(@metadata[:versions].last[:created_at])
    assert_equal 'yanked', @package.versions.find_by!(number: '1.5.1').status
  end

  def assert_latest_release(number, published_at)
    @package.reload
    assert_equal number, @package.latest_release_number
    assert_equal published_at, @package.latest_release_published_at
    assert_equal [number], @package.versions.where(latest: true).pluck(:number)
  end
end
