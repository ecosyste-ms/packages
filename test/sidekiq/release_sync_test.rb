require "test_helper"
require 'rake'

class ReleaseSyncTest < ActionDispatch::IntegrationTest
  setup do
    SyncPackageWorker.clear
    SyncPackageByIdWorker.clear
    @registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @published_at = 1.hour.ago.change(usec: 0)
    @package = @registry.packages.create!(name: 'lazy_static', ecosystem: 'cargo', status: 'active', last_synced_at: 2.hours.ago,
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
    SyncPackageByIdWorker.clear
  end

  test 'recent update polling imports a release within a day of the previous sync' do
    @registry.packages.create!(name: 'recently_synced', ecosystem: 'cargo', last_synced_at: 5.minutes.ago)
    stub_request(:get, 'https://crates.io/api/v1/summary')
      .to_return(status: 200, body: { just_updated: [{ name: 'lazy_static' }, { name: 'recently_synced' }], new_crates: [] }.to_json)

    Registry.sync_all_recently_updated_packages_async

    assert_equal 2, SyncPackageWorker.jobs.size
    args = SyncPackageWorker.jobs.find { |job| job['args'][1] == 'lazy_static' }['args']
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

  test 'ping imports a release for a top one percent package after twelve hours' do
    @package.update!(rankings: { average: 0.5 }, last_synced_at: 13.hours.ago)

    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)

    assert_response :success
    assert_equal 1, SyncPackageByIdWorker.jobs.size
    SyncPackageByIdWorker.new.perform(*SyncPackageByIdWorker.jobs.first['args'])
    assert_latest_release '1.5.1', @published_at
  end

  test 'ping retains the daily cooldown outside the top one percent and without a ranking' do
    [{ average: 1 }, {}, { average: nil }].each do |rankings|
      @package.update!(rankings: rankings, last_synced_at: 13.hours.ago)

      get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)

      assert_response :success
      assert_empty SyncPackageByIdWorker.jobs
    end
  end

  test 'popular packages inside the cooldown are deferred until twelve hours after the last sync' do
    @package.update!(rankings: { average: 0.5 }, last_synced_at: 11.hours.ago)

    get ping_api_v1_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_empty SyncPackageByIdWorker.jobs
    SyncPackageWorker.new.perform(@registry.id, @package.name)

    assert_equal '1.5.0', @package.reload.latest_release_number
    assert_equal 1, SyncPackageWorker.jobs.size
    assert_in_delta @package.last_synced_at.to_f + 12.hours, SyncPackageWorker.jobs.first['at'], 1
  end

  test 'the popular package sweep passes rankings through to the cooldown check' do
    @package.update!(rankings: { average: 0.5 }, last_synced_at: 13.hours.ago)
    @registry.packages.create!(name: 'less-popular', ecosystem: 'cargo', status: 'active', rankings: { average: 1.5 }, last_synced_at: 13.hours.ago)

    invoke_task('packages:sync_least_recent_top')

    assert_equal [[@registry.id, @package.id]], SyncPackageByIdWorker.jobs.map { |job| job['args'] }
    SyncPackageByIdWorker.new.perform(*SyncPackageByIdWorker.jobs.first['args'])
    assert_latest_release '1.5.1', @published_at
  end

  test 'polling retains one deferred refresh after a release leaves the feed' do
    freeze_time do
      @package.update!(last_synced_at: 5.minutes.ago)
      stub_request(:get, 'https://crates.io/api/v1/summary')
        .to_return(body: { just_updated: [{ name: 'lazy_static' }], new_crates: [] }.to_json)

      2.times { invoke_task('packages:sync_recent') }

      assert_equal 1, SyncPackageWorker.jobs.size
      job = SyncPackageWorker.jobs.first
      assert_equal [@registry.id, @package.name, true], job['args']
      assert_in_delta 5.minutes.from_now.to_f, job['at'], 1

      stub_request(:get, 'https://crates.io/api/v1/summary')
        .to_return(body: { just_updated: [], new_crates: [] }.to_json)
      travel 6.minutes
      invoke_task('packages:sync_recent')
      assert_equal 1, SyncPackageWorker.jobs.size
      SyncPackageWorker.new.perform(*job['args'])

      assert_latest_release '1.5.1', @published_at
    end
  end

  def invoke_task(name)
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  ensure
    Rake::Task[name].reenable
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

  test 'version update worker refreshes npm dist-tags before selecting the latest release' do
    registry = Registry.create!(name: 'registry.npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    funding = { 'url' => 'https://example.com/funding' }
    package = registry.packages.create!(name: 'fresh', ecosystem: 'npm',
      metadata: { 'dist-tags' => { 'latest' => '1.0.0' }, 'funding' => funding },
      latest_release_number: '1.0.0', latest_release_published_at: 1.year.ago)
    package.versions.create!(number: '1.0.0', published_at: 1.year.ago, latest: true)
    metadata = {
      '_id' => 'fresh',
      'versions' => {
        '1.0.0' => { 'name' => 'fresh', 'version' => '1.0.0', 'license' => 'MIT' },
        '2.0.0' => { 'name' => 'fresh', 'version' => '2.0.0', 'license' => 'MIT' }
      },
      'time' => { '1.0.0' => 1.year.ago.iso8601, '2.0.0' => @published_at.iso8601 }
    }
    stub_request(:get, 'https://api.npmjs.org/downloads/point/last-month/fresh')
      .to_return(status: 200, body: { downloads: 100 }.to_json)

    ['2.0.0', '1.0.0', nil].each do |tag|
      metadata['dist-tags'] = tag ? { 'latest' => tag } : nil
      stub_request(:get, 'https://registry.npmjs.org/fresh')
        .to_return(status: 200, body: metadata.to_json)

      UpdateVersionsWorker.new.perform(package.id)

      package.reload
      expected_latest = tag || '2.0.0'
      assert_equal expected_latest, package.latest_release_number
      assert_equal Time.iso8601(metadata['time'][expected_latest]), package.latest_release_published_at
      assert_equal [expected_latest], package.versions.where(latest: true).pluck(:number)
      assert_equal metadata['dist-tags'] || {}, package.metadata['dist-tags'] || {}
      assert_equal funding, package.metadata['funding']
      assert_equal 2, package.versions_count
    end
  end

  def assert_latest_release(number, published_at)
    @package.reload
    assert_equal number, @package.latest_release_number
    assert_equal published_at, @package.latest_release_published_at
    assert_equal [number], @package.versions.where(latest: true).pluck(:number)
  end
end
