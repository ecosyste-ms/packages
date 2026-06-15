require "test_helper"

class LiveEventTest < ActiveSupport::TestCase
  teardown do
    ENV.delete('LIVE_WEBHOOK_URL')
    ENV.delete('LIVE_WEBHOOK_TOKEN')
  end

  test 'enabled? is false without env' do
    refute LiveEvent.enabled?
  end

  test 'enabled? is true with env' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://live.test/ingest'
    assert LiveEvent.enabled?
  end

  test 'emit does nothing without env' do
    assert_nil LiveEvent.emit([{ event: 'version.created' }])
  end

  test 'emit does nothing with empty events' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://live.test/ingest'
    assert_nil LiveEvent.emit([])
    assert_nil LiveEvent.emit(nil)
  end

  test 'emit posts events with bearer token' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://live.test/ingest'
    ENV['LIVE_WEBHOOK_TOKEN'] = 'secret'

    stub = stub_request(:post, 'http://live.test/ingest')
      .with(
        headers: {
          'Content-Type' => 'application/json',
          'Authorization' => 'Bearer secret',
          'User-Agent' => 'packages.ecosyste.ms'
        },
        body: { events: [{ event: 'version.created', name: 'foo' }] }.to_json
      )
      .to_return(status: 200)

    LiveEvent.emit({ event: 'version.created', name: 'foo' })
    assert_requested stub
  end

  test 'emit posts without auth header when token unset' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://live.test/ingest'

    stub_request(:post, 'http://live.test/ingest')
      .with { |req| !req.headers.key?('Authorization') }
      .to_return(status: 200)

    LiveEvent.emit({ event: 'package.created' })
    assert_requested :post, 'http://live.test/ingest'
  end

  test 'emit swallows connection errors' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://live.test/ingest'
    stub_request(:post, 'http://live.test/ingest').to_raise(Faraday::ConnectionFailed)

    assert_nothing_raised do
      assert_nil LiveEvent.emit({ event: 'version.created' })
    end
  end

  test 'emit swallows timeout errors' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://live.test/ingest'
    stub_request(:post, 'http://live.test/ingest').to_timeout

    assert_nothing_raised do
      assert_nil LiveEvent.emit({ event: 'version.created' })
    end
  end

  test 'emit swallows invalid URI errors' do
    ENV['LIVE_WEBHOOK_URL'] = 'http://[invalid'

    assert_nothing_raised do
      assert_nil LiveEvent.emit({ event: 'version.created' })
    end
  end
end
