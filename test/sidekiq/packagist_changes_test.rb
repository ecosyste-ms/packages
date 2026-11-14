require 'test_helper'
require 'rake'

class PackagistChangesTest < ActiveSupport::TestCase
  setup do
    SyncPackagistChangeWorker.clear
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    @time = Time.current.change(usec: 0)
    @cursor = (@time.to_i - 900) * 10_000
    @next_cursor = @time.to_i * 10_000 + 1
    @registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist',
      metadata: {'other' => 'preserved', Ecosystem::Packagist::CHANGES_STATE_KEY => {'cursor' => @cursor}})
    @package = @registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', status: 'active', last_synced_at: 1.minute.ago)
    @package.versions.create!(number: '3.0.0', published_at: 2.years.ago)
    stub_request(:get, 'https://packagist.org/packages/psr/log.json')
      .to_return(body: file_fixture('packagist/log.json.1'))
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(body: {packages: {'psr/log' => [{version: 'dev-master'}]}}.to_json, headers: {'Last-Modified' => @time.httpdate})
    tagged_metadata
  end

  teardown do
    SyncPackagistChangeWorker.clear
  end

  test 'scheduled discovery imports releases even just after a previous sync' do
    changes([action])
    poll

    assert_equal [[@registry.id, action]], SyncPackagistChangeWorker.jobs.map { |job| job['args'] }
    assert_equal @next_cursor, state['cursor']
    assert_equal 'preserved', @registry.metadata['other']
    SyncPackagistChangeWorker.new.perform(*SyncPackagistChangeWorker.jobs.first['args'])

    assert_equal 12, @package.versions.count
    assert_equal '3.0.2', @package.reload.latest_release_number
    assert_equal '>=8.0.0', @package.versions.find_by!(number: '3.0.2').metadata['php_version']
    assert_equal 3, @package.maintainers.count
    assert_not_requested(:get, %r{/feeds/})
  end

  test 'more than one hundred changes survive discovery and rate budgets' do
    @registry.update!(metadata: @registry.metadata.merge('rate_limit' => 1))
    events = 105.times.map { |i| action("vendor/package#{i}") }
    changes(events)
    @registry.sync_recently_updated_packages_async(period: 2.seconds)

    assert_equal events, SyncPackagistChangeWorker.jobs.map { |job| job['args'].last }
    assert_equal @next_cursor, state['cursor']
    assert_operator SyncPackagistChangeWorker.jobs.last['at'], :>=, Time.current.to_f + 100
    previous_end = state['enqueue_at']
    changes([action('vendor/later')], since: @next_cursor, timestamp: @next_cursor + 1)
    @registry.sync_recently_updated_packages_async(period: 2.seconds)
    assert_operator SyncPackagistChangeWorker.jobs.last['at'], :>=, previous_end
  end

  test 'partial enqueue failure leaves the cursor unchanged and replay retains every event' do
    changes([action, action('vendor/second')])
    failed = mock
    failed.expects(:perform_bulk).returns(['accepted', nil])
    SyncPackagistChangeWorker.expects(:set).returns(failed)
    Rails.logger.expects(:error).with(regexp_matches(/Recent package sync failed for packagist\.org:/))
    poll
    assert_equal @cursor, state['cursor']
    SyncPackagistChangeWorker.unstub(:set)
    poll
    assert_equal 2, SyncPackagistChangeWorker.jobs.size
    assert_equal @next_cursor, state['cursor']
  end

  test 'network failures and invalid feeds do not advance discovery' do
    request = stub_request(:get, "https://packagist.org/metadata/changes.json?since=#{@cursor}")
    Rails.logger.expects(:error).with(regexp_matches(/Recent package sync failed for packagist\.org:/)).times(4)
    request.to_return(status: 503)
    poll
    request.to_return(body: 'invalid')
    poll
    request.to_return(body: {timestamp: @next_cursor, actions: [action.merge('type' => 'unknown')]}.to_json)
    poll
    request.to_return(body: {timestamp: @cursor - 1, actions: []}.to_json)
    poll
    assert_equal @cursor, state['cursor']
    assert_empty SyncPackagistChangeWorker.jobs
  end

  test 'empty polls persist the returned cursor and initial polling looks back fifteen minutes' do
    @registry.update!(metadata: {})
    freeze_time do
      initial = 15.minutes.ago.to_i * 10_000
      changes([], since: initial)
      poll
      assert_equal @next_cursor, state['cursor']
      assert_empty SyncPackagistChangeWorker.jobs
    end
  end

  test 'stale CDN metadata retries without touching package state or the cached snapshot' do
    synced_at = @package.last_synced_at
    tagged_metadata(last_modified: (@time - 1).httpdate)
    changes([action])
    poll
    job = SyncPackagistChangeWorker.jobs.first
    assert_raises(RuntimeError) { SyncPackagistChangeWorker.new.perform(*job['args']) }
    assert_equal synced_at, @package.reload.last_synced_at
    assert_equal ['3.0.0'], @package.versions.pluck(:number)
    assert_nil Rails.cache.read(['packagist', 'tagged_versions', 'psr/log'])

    tagged_metadata
    SyncPackagistChangeWorker.new.perform(*job['args'])
    assert_equal 12, @package.versions.count
  end

  test 'a stale cached body with HTTP 304 is retried' do
    Rails.cache.write(['packagist', 'tagged_versions', 'psr/log'],
      {'body' => file_fixture('packagist/log.p2.json').read, 'last_modified' => (@time - 1).httpdate})
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 304)
    assert_raises(RuntimeError) { SyncPackagistChangeWorker.new.perform(@registry.id, action) }
    assert_equal ['3.0.0'], @package.versions.pluck(:number)
  end

  test 'identical content still needs a timestamp at least as recent as its change event' do
    SyncPackageWorker.new.perform(@registry.id, @package.name, true)
    before = @package.reload.attributes
    cached = Rails.cache.read(['packagist', 'tagged_versions', @package.name])
    tagged_metadata(last_modified: (@time - 1).httpdate)

    assert_raises(Ecosystem::Packagist::RetryableError) do
      SyncPackagistChangeWorker.new.perform(@registry.id, action)
    end

    assert_equal before, @package.reload.attributes
    assert_equal cached, Rails.cache.read(['packagist', 'tagged_versions', @package.name])
  end

  test 'fresh HTTP 304 reuses the cached body' do
    Rails.cache.write(['packagist', 'tagged_versions', 'psr/log'],
      {'body' => file_fixture('packagist/log.p2.json').read, 'last_modified' => @time.httpdate})
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .with(headers: {'If-Modified-Since' => @time.httpdate}).to_return(status: 304)
    SyncPackagistChangeWorker.new.perform(@registry.id, action)
    assert_equal 12, @package.versions.count
  end

  test 'missing last modified and transient enrichment failures are retried' do
    tagged_metadata(last_modified: nil)
    assert_raises(RuntimeError) { SyncPackagistChangeWorker.new.perform(@registry.id, action) }
    Rails.cache.clear
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(status: 503)
    assert_raises(RuntimeError) { SyncPackagistChangeWorker.new.perform(@registry.id, action) }
    assert_equal ['3.0.0'], @package.versions.pluck(:number)
  end

  test 'development events check development freshness without requiring newer tagged metadata' do
    tagged_metadata(last_modified: (@time - 1.day).httpdate)
    event = action('psr/log~dev')
    changes([event])
    poll
    SyncPackagistChangeWorker.new.perform(*SyncPackagistChangeWorker.jobs.first['args'])
    assert_equal 12, @package.versions.count
    assert_not @package.versions.where('number LIKE ?', 'dev-%').exists?
  end

  test 'stale development metadata is retried before package writes' do
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(body: '{}', headers: {'Last-Modified' => (@time - 1).httpdate})
    assert_raises(RuntimeError) { SyncPackagistChangeWorker.new.perform(@registry.id, action('psr/log~dev')) }
    assert_equal ['3.0.0'], @package.versions.pluck(:number)
  end

  test 'delete events mark existing packages removed and retain their versions' do
    changes([action.merge('type' => 'delete')])
    poll
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 404)
    SyncPackagistChangeWorker.new.perform(*SyncPackagistChangeWorker.jobs.first['args'])
    assert_equal 'removed', @package.reload[:status]
    assert_equal ['3.0.0'], @package.versions.pluck(:number)
  end

  test 'a delayed delete event refreshes a package that has returned upstream' do
    @package.update!(status: 'removed')
    SyncPackagistChangeWorker.new.perform(@registry.id, action.merge('type' => 'delete'))
    assert_equal 'active', @package.reload[:status]
    assert_equal 12, @package.versions.count
    assert_requested(:get, 'https://repo.packagist.org/p2/psr/log.json', times: 1)
  end

  test 'restoring a deleted package restores only releases in the current snapshot before selecting latest' do
    SyncPackagistChangeWorker.new.perform(@registry.id, action)
    absent = @package.versions.create!(number: '99.0.0', published_at: @time)
    latest = @package.versions.find_by!(number: '3.0.2')
    dependency = latest.dependencies.create!(package_name: 'vendor/dependency', ecosystem: 'packagist', requirements: '*', kind: 'runtime')
    original_ids = @package.versions.order(:id).pluck(:id)
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 404)
    SyncPackagistChangeWorker.new.perform(@registry.id, action.merge('type' => 'delete'))
    assert_equal 13, @package.versions.where(status: 'removed').count

    tagged_metadata
    SyncPackagistChangeWorker.new.perform(@registry.id, action)

    assert_equal 'active', @package.reload[:status]
    assert_equal 12, @package.versions.active.count
    assert_equal 'removed', absent.reload.status
    assert_equal original_ids, @package.versions.order(:id).pluck(:id)
    assert_equal '3.0.2', @package.latest_release_number
    assert_equal ['3.0.2'], @package.versions.where(latest: true).pluck(:number)
    assert Dependency.exists?(dependency.id)
  end

  test 'restoring removed releases preserves other statuses and packages' do
    @package.versions.first.update!(status: 'removed')
    yanked = @package.versions.create!(number: '3.0.1', status: 'yanked')
    other = @registry.packages.create!(name: 'vendor/other', ecosystem: 'packagist')
    other_version = other.versions.create!(number: '3.0.0', status: 'removed')

    SyncPackagistChangeWorker.new.perform(@registry.id, action)

    assert_nil @package.versions.find_by!(number: '3.0.0').status
    assert_equal 'yanked', yanked.reload.status
    assert_equal 'removed', other_version.reload.status
  end

  test 'a cached pre-deletion snapshot is retried instead of restoring the package' do
    @package.update!(status: 'removed')
    tagged_metadata(last_modified: (@time - 1).httpdate)
    assert_raises(RuntimeError) do
      SyncPackagistChangeWorker.new.perform(@registry.id, action.merge('type' => 'delete'))
    end
    assert_equal 'removed', @package.reload[:status]
    assert_equal ['3.0.0'], @package.versions.pluck(:number)
    assert_equal ['removed'], @package.versions.pluck(:status)
  end

  test 'deletion matches existing capitalized names without creating a package for unknown names' do
    @package.update!(name: 'PSR/Log')
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 404)
    SyncPackagistChangeWorker.new.perform(@registry.id, action.merge('type' => 'delete'))
    assert_equal 'removed', @package.reload[:status]
    stub_request(:get, 'https://repo.packagist.org/p2/vendor/unknown.json').to_return(status: 404)
    assert_no_difference('Package.count') do
      SyncPackagistChangeWorker.new.perform(@registry.id, action('vendor/unknown').merge('type' => 'delete'))
    end
  end

  test 'delete check failures do not mark packages removed' do
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 503)
    assert_raises(RuntimeError) do
      SyncPackagistChangeWorker.new.perform(@registry.id, action.merge('type' => 'delete'))
    end
    assert_equal 'active', @package.reload[:status]
  end

  test 'resync reconciles known packages including inactive ones and discovers missing packages' do
    @package.update!(status: 'removed')
    changes([{'type' => 'resync', 'package' => '*', 'time' => @time.to_i}])
    poll
    assert_equal @next_cursor, state['cursor']
    assert_equal 'catalogue', state.dig('recovery', 'phase')
    assert_equal ['psr/log'], SyncPackagistChangeWorker.jobs.map { |j| j['args'].last['package'] }
    SyncPackagistChangeWorker.new.perform(*SyncPackagistChangeWorker.jobs.first['args'])
    assert_equal 'active', @package.reload[:status]

    changes([action('vendor/new')], since: @next_cursor, timestamp: @next_cursor + 1)
    stub_request(:get, 'https://packagist.org/packages/list.json')
      .to_return(body: {packageNames: ['psr/log', 'vendor/missing']}.to_json)
    poll
    assert_equal ['psr/log', 'vendor/new', 'vendor/missing'], SyncPackagistChangeWorker.jobs.map { |j| j['args'].last['package'] }
    assert_nil state['recovery']
  end

  test 'resync checkpoints known packages in bounded batches while newer events continue' do
    stub_const(Ecosystem::Packagist, :RECOVERY_BATCH_SIZE, 1) do
      changes([{'type' => 'resync', 'package' => '*', 'time' => @time.to_i}])
      poll
      assert_equal 'psr/log', state.dig('recovery', 'after')
      @registry.packages.create!(name: 'vendor/z', ecosystem: 'packagist')
      changes([action('vendor/new')], since: @next_cursor, timestamp: @next_cursor + 1)
      poll
      assert_equal 'vendor/z', state.dig('recovery', 'after')
      assert_equal ['psr/log', 'vendor/new', 'vendor/z'], SyncPackagistChangeWorker.jobs.map { |j| j['args'].last['package'] }
    end
  end

  %w[known catalogue].each do |phase|
    test "a new resync restarts an unfinished #{phase} recovery" do
      @registry.update!(metadata: @registry.metadata.merge(Ecosystem::Packagist::CHANGES_STATE_KEY =>
        {'cursor' => @cursor, 'recovery' => {'phase' => phase, 'after' => 'zzzz/already-scanned'}}))
      changes([{'type' => 'resync', 'package' => '*', 'time' => @time.to_i}])
      stub_request(:get, 'https://packagist.org/packages/list.json')
        .to_return(body: {packageNames: ['aaa/missed', 'psr/log']}.to_json)

      poll

      assert_equal ['psr/log'], SyncPackagistChangeWorker.jobs.map { |job| job['args'].last['package'] }
      assert_equal({'phase' => 'catalogue', 'after' => ''}, state['recovery'])
      changes([], since: @next_cursor, timestamp: @next_cursor + 1)
      poll
      assert_equal ['psr/log', 'aaa/missed'], SyncPackagistChangeWorker.jobs.map { |job| job['args'].last['package'] }
      assert_nil state['recovery']
    end
  end

  test 'failed catalogue recovery retains its checkpoint after advancing the live feed' do
    @registry.update!(metadata: @registry.metadata.merge(Ecosystem::Packagist::CHANGES_STATE_KEY =>
      {'cursor' => @cursor, 'recovery' => {'phase' => 'catalogue', 'after' => 'psr/log'}}))
    changes([])
    stub_request(:get, 'https://packagist.org/packages/list.json').to_return(status: 503)
    Rails.logger.expects(:error).with(regexp_matches(/Recent package sync failed for packagist\.org:/))
    poll
    assert_equal @next_cursor, state['cursor']
    assert_equal 'psr/log', state.dig('recovery', 'after')
  end

  test 'a failed recovery enqueue retains its checkpoint' do
    changes([{'type' => 'resync', 'package' => '*', 'time' => @time.to_i}])
    failed = mock
    failed.expects(:perform_bulk).returns([nil])
    SyncPackagistChangeWorker.expects(:set).returns(failed)
    Rails.logger.expects(:error).with(regexp_matches(/Recent package sync failed for packagist\.org:/))
    poll
    assert_equal @next_cursor, state['cursor']
    assert_equal({'phase' => 'known', 'after' => ''}, state['recovery'])
  end

  test 'catalogue recovery skips known names and resumes after its missing package budget' do
    @registry.update!(metadata: @registry.metadata.merge(Ecosystem::Packagist::CHANGES_STATE_KEY =>
      {'cursor' => @cursor, 'recovery' => {'phase' => 'catalogue', 'after' => ''}}))
    stub_request(:get, 'https://packagist.org/packages/list.json')
      .to_return(body: {packageNames: ['vendor/missing', 'psr/log', 'aaa/missing']}.to_json)
    stub_const(Ecosystem::Packagist, :RECOVERY_BATCH_SIZE, 1) do
      changes([])
      poll
      assert_equal 'aaa/missing', state.dig('recovery', 'after')
      changes([], since: @next_cursor, timestamp: @next_cursor + 1)
      poll
      assert_nil state['recovery']
      assert_equal ['aaa/missing', 'vendor/missing'], SyncPackagistChangeWorker.jobs.map { |j| j['args'].last['package'] }
    end
  end

  test 'recovery waits for spare rate budget after live events are queued' do
    freeze_time do
      @registry.update!(metadata: @registry.metadata.merge('rate_limit' => 1))
      changes([{'type' => 'resync', 'package' => '*', 'time' => @time.to_i}, action('vendor/a'), action('vendor/b')])
      @registry.sync_recently_updated_packages_async(period: 2.seconds)
      assert_equal 2, SyncPackagistChangeWorker.jobs.size
      assert_equal({'phase' => 'known', 'after' => ''}, state['recovery'])
      travel 3.seconds
      changes([], since: @next_cursor, timestamp: @next_cursor + 1)
      @registry.sync_recently_updated_packages_async(period: 2.seconds)
      assert_equal 'psr/log', SyncPackagistChangeWorker.jobs.last['args'].last['package']
      assert_equal 'catalogue', state.dig('recovery', 'phase')
    end
  end

  def action(name = 'psr/log')
    {'type' => 'update', 'package' => name, 'time' => @time.to_i}
  end

  def changes(actions, since: @cursor, timestamp: @next_cursor)
    stub_request(:get, "https://packagist.org/metadata/changes.json?since=#{since}")
      .to_return(body: {timestamp: timestamp, actions: actions}.to_json)
  end

  def tagged_metadata(last_modified: @time.httpdate)
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .to_return(body: file_fixture('packagist/log.p2.json'), headers: last_modified ? {'Last-Modified' => last_modified} : {})
  end

  def poll
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['packages:sync_recent'].reenable
    Rake::Task['packages:sync_recent'].invoke
  ensure
    Rake::Task['packages:sync_recent'].reenable
  end

  def state
    @registry.reload.metadata.fetch(Ecosystem::Packagist::CHANGES_STATE_KEY)
  end
end
