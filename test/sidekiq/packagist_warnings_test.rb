require 'test_helper'
require 'sidekiq/job_retry'
require 'sidekiq/api'

class PackagistWarningsTest < ActiveSupport::TestCase
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    @time = Time.current.change(usec: 0)
    @registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @package = @registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', last_synced_at: 2.days.ago)
    @version = @package.versions.create!(number: '3.0.0', metadata: {'preserved' => true})
    @action = {'package' => 'psr/log', 'type' => 'update', 'time' => @time.to_i}
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(body: file_fixture('packagist/log.json.1'))
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(body: {packages: {'psr/log' => [{version: 'dev-master'}]}}.to_json, headers: {'Last-Modified' => @time.httpdate})
    tagged
  end

  %w[sync by_id versions changes refresh].each do |path|
    test "#{path} retries missing tagged metadata without changing stored releases or status" do
      stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 404)
      original = @package.attributes
      original_version = @version.attributes
      Rails.logger.expects(:warn).with('Tagged metadata for psr/log returned HTTP 404')

      error = assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }

      assert_ignored(error)
      assert_equal original, @package.reload.attributes
      assert_equal original_version, @version.reload.attributes
      assert_nil Rails.cache.read(['packagist', 'tagged_versions', 'psr/log'])
      assert_not_requested(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      tagged
      perform(path)
      assert_equal 12, @package.versions.count
      assert_equal 'active', @package.reload[:status]
    end
  end

  test 'stale metadata logs the package and both timestamps and remains retryable' do
    tagged(last_modified: (@time - 60).httpdate)
    original = @package.attributes
    Rails.logger.expects(:warn).with(regexp_matches(/psr\/log, expected=#{@time.to_i}, last_modified=/))
    error = assert_raises(Ecosystem::Packagist::RetryableError) { perform('changes') }
    assert_ignored(error)
    assert_equal original, @package.reload.attributes
    assert_nil Rails.cache.read(['packagist', 'tagged_versions', 'psr/log'])
  end

  test 'development metadata failures remain retryable before any package writes' do
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json').to_return(status: 404)
    @action['package'] = 'psr/log~dev'
    error = assert_raises(Ecosystem::Packagist::RetryableError) { perform('changes') }
    assert_ignored(error)
    assert_includes error.message, 'Development metadata for psr/log returned HTTP 404'
    assert_equal [@version.id], @package.versions.pluck(:id)
  end

  test 'transient enrichment failures propagate through by-id sync without checking removal' do
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(status: 503)
    original = @package.attributes
    error = assert_raises(Ecosystem::Packagist::RetryableError) { perform('by_id') }
    assert_ignored(error)
    assert_equal original, @package.reload.attributes
    assert_not_requested(:head, %r{packagist.org})
  end

  test 'malformed enrichment is an actionable error rather than a failed sync result' do
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(body: 'invalid json')
    assert_raises(JSON::ParserError) { perform('by_id') }
    assert_not_requested(:head, %r{packagist.org})
    assert_equal [@version.id], @package.versions.pluck(:id)
  end

  test 'invalid metadata and unexpected HTTP failures are not warning exceptions' do
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 403)
    error = assert_raises(RuntimeError) { perform('sync') }
    assert_instance_of RuntimeError, error
    tagged(body: {packages: {}}.to_json)
    assert_raises(KeyError) { perform('sync') }
    assert_equal [@version.id], @package.versions.pluck(:id)
  end

  test 'malware mismatch warns and preserves the previous classification for retry' do
    @registry.update!(metadata: {'packagist_malware' => {'packages' => {'psr/log' => '3.0.0'}}})
    @version.update!(status: 'malware', metadata: {'malware' => [{'constraint' => '3.0.0', 'source' => 'packagist'}]})
    original = @version.attributes
    tagged(body: {packages: {'psr/log' => []}, filter: {malware: [{constraint: '4.0.0', source: 'packagist'}]}}.to_json)
    error = assert_raises(Ecosystem::Packagist::RetryableError) { SyncPackagistMalwareWorker.new.perform(@registry.id, 'psr/log') }
    assert_ignored(error)
    assert_includes error.message, 'psr/log, expected=["3.0.0"], actual=["4.0.0"]'
    assert_equal original, @version.reload.attributes
  end

  test 'Sidekiq schedules a warning retry and reports it only after exhausting retries' do
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 404)
    config = Sidekiq::Config.new
    Sidekiq.stubs(:configure_server).yields(config)
    load Rails.root.join('config/initializers/packagist_error_reporting.rb')
    retryer = Sidekiq::JobRetry.new(config)
    worker = SyncPackagistChangeWorker.new
    job = {'class' => worker.class.name, 'args' => [@registry.id, @action], 'jid' => SecureRandom.hex(12), 'retry' => 1, 'queue' => 'critical'}
    Appsignal.expects(:report_error).never

    assert_raises(Sidekiq::JobRetry::Handled) { retryer.local(worker, job.to_json, 'critical') { worker.perform(*job['args']) } }
    retry_job = Sidekiq::RetrySet.new.find_job(job['jid'])
    assert retry_job
    assert_equal 'Ecosystem::Packagist::RetryableError', retry_job['error_class']
    assert_equal 0, retry_job['retry_count']
    Appsignal.unstub(:report_error)
    transaction = mock
    transaction.expects(:set_action).with('SyncPackagistChangeWorker#perform')
    transaction.expects(:set_namespace).with('background')
    transaction.expects(:add_tags).with(job_id: job['jid'], retry_count: 1)
    transaction.expects(:add_function_parameters)
    Appsignal.expects(:report_error).with { |error| error.is_a?(PackagistErrorReporting::RetriesExhausted) && error.message.include?('psr/log') }.yields(transaction)
    assert_raises(Sidekiq::JobRetry::Handled) { retryer.local(worker, retry_job.item.to_json, 'critical') { worker.perform(*job['args']) } }
    assert Sidekiq::DeadSet.new.find_job(job['jid'])
    assert_equal [@version.id], @package.versions.pluck(:id)
  ensure
    Sidekiq::RetrySet.new.find_job(job['jid'])&.delete if job
    Sidekiq::DeadSet.new.find_job(job['jid'])&.delete if job
  end

  def perform(path)
    case path
    when 'sync' then SyncPackageWorker.new.perform(@registry.id, 'psr/log', true)
    when 'by_id' then SyncPackageByIdWorker.new.perform(@registry.id, @package.id)
    when 'versions' then UpdateVersionsWorker.new.perform(@package.id)
    else SyncPackagistChangeWorker.new.perform(@registry.id, @action.merge('type' => path == 'refresh' ? 'refresh' : 'update'))
    end
  end

  def tagged(last_modified: @time.httpdate, body: file_fixture('packagist/log.p2.json').read)
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(body: body, headers: {'Last-Modified' => last_modified})
  end

  def assert_ignored(error)
    ignored = YAML.load_file(Rails.root.join('config/appsignal.yml')).fetch('production').fetch('ignore_errors')
    assert_includes ignored, error.class.name
    assert_not_includes ignored, PackagistErrorReporting::RetriesExhausted.name
  end
end
