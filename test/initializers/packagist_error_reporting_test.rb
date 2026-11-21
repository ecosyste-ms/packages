require 'test_helper'

class PackagistErrorReportingTest < ActiveSupport::TestCase
  setup do
    reporter = ActiveSupport::ErrorReporter.new
    reporter.subscribe(Appsignal::Integrations::RailsErrorReporterSubscriber)
    Rails.stubs(:error).returns(reporter)
    ActiveSupport.stubs(:error_reporter).returns(reporter)
  end

  test 'Rails cache size warnings for Packagist are logged without reporting an exception' do
    client = Dalli::Client.new('localhost:11211')
    client.stubs(:set).raises(Dalli::ValueOverMaxSize, 'Value for packagist/tagged_versions/vendor/package over max size: 1048576 <= 2001064')
    ActiveSupport::Cache::MemCacheStore.stubs(:build_mem_cache).returns(client)
    cache = ActiveSupport::Cache::MemCacheStore.new('localhost:11211', pool: false)
    Rails.logger.expects(:warn).with(regexp_matches(/Packagist cache write skipped/))
    Appsignal.expects(:report_error).never

    assert_nil cache.write(['packagist', 'tagged_versions', 'vendor/package'], {'body' => 'metadata'})
  end

  test 'other cache errors and unhandled size errors are still reported' do
    cases = [
      [Dalli::DalliError.new('Connection failed'), true, :warning, 'mem_cache_store.active_support'],
      [Dalli::ValueOverMaxSize.new('Value for another/key over max size'), true, :warning, 'mem_cache_store.active_support'],
      [Dalli::ValueOverMaxSize.new('Value for packagist/key over max size'), false, :error, 'mem_cache_store.active_support'],
      [Dalli::ValueOverMaxSize.new('Value for packagist/key over max size'), true, :warning, 'other.source']
    ]
    cases.each do |error, handled, severity, source|
      Appsignal.expects(:report_error).with(error, anything)
      Rails.error.report(error, handled: handled, severity: severity, source: source)
    end
  end
end
