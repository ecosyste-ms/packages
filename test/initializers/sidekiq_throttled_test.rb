require "test_helper"

class SidekiqThrottledTest < ActiveSupport::TestCase
  setup do
    Registry.reset_throttle_cache
    @npm = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm', rate_limit: 2)
    @gems = Registry.create!(name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @strategy = Sidekiq::Throttled::Registry.get(:registry_host)
    reset_buckets
  end

  teardown do
    reset_buckets
    Registry.reset_throttle_cache
  end

  def reset_buckets
    Sidekiq.redis do |r|
      keys = r.scan("MATCH", "throttled:*", "COUNT", 1000).to_a
      r.call("DEL", *keys) if keys.any?
    end
  end

  test "Registry.host_for and rate_limit_for read from cache" do
    assert_equal 'registry.npmjs.org', Registry.host_for(@npm.id)
    assert_equal 2, Registry.rate_limit_for(@npm.id)
    assert_equal 'rubygems.org', Registry.host_for(@gems.id)
    assert_nil Registry.rate_limit_for(@gems.id)
  end

  test "extract_host handles schemeless and invalid urls" do
    assert_equal 'rubygems.org', Registry.extract_host('rubygems.org')
    assert_equal 'rubygems.org', Registry.extract_host('https://rubygems.org/api')
    assert_equal 'not a url', Registry.extract_host('not a url')
  end

  test "throttle cache expires after TTL" do
    assert_equal 2, Registry.rate_limit_for(@npm.id)
    @npm.update_column(:metadata, @npm.metadata.merge('rate_limit' => 5))
    assert_equal 2, Registry.rate_limit_for(@npm.id)
    Process.stubs(:clock_gettime).returns(Registry.instance_variable_get(:@throttle_cache_expires_at) + 1)
    assert_equal 5, Registry.rate_limit_for(@npm.id)
  end

  test "rate_limit is stored in metadata and must be positive when set" do
    refute @npm.update(rate_limit: 0)
    refute @npm.update(rate_limit: -1)
    refute @npm.update(rate_limit: '10')
    assert @npm.update(rate_limit: 3)
    assert_equal({ 'rate_limit' => 3 }, @npm.metadata)
    assert @npm.update(rate_limit: nil)
    assert_equal({}, @npm.metadata)
  end

  test "rate_limit writer preserves other metadata keys" do
    @gems.update!(metadata: { 'api_url' => 'https://x' })
    @gems.update!(rate_limit: 4)
    assert_equal({ 'api_url' => 'https://x', 'rate_limit' => 4 }, @gems.metadata)
  end

  test "workers are aliased to the registry_host strategy" do
    assert_same @strategy, Sidekiq::Throttled::Registry.get('SyncPackageWorker')
    assert_same @strategy, Sidekiq::Throttled::Registry.get('SyncPackageVersionWorker')
  end

  test "nil rate_limit means never throttled" do
    10.times do
      refute @strategy.throttled?(SecureRandom.hex, @gems.id, 'pkg')
    end
  end

  test "throttles after rate_limit jobs within the period" do
    refute @strategy.throttled?(SecureRandom.hex, @npm.id, 'a')
    refute @strategy.throttled?(SecureRandom.hex, @npm.id, 'b')
    assert @strategy.throttled?(SecureRandom.hex, @npm.id, 'c')
  end

  test "registries with the same host share a bucket" do
    npm2 = Registry.create!(name: 'npm-mirror', url: 'https://registry.npmjs.org/mirror', ecosystem: 'npm', rate_limit: 2)
    assert_equal Registry.host_for(@npm.id), Registry.host_for(npm2.id)
    refute @strategy.throttled?(SecureRandom.hex, @npm.id, 'a')
    refute @strategy.throttled?(SecureRandom.hex, npm2.id, 'a')
    assert @strategy.throttled?(SecureRandom.hex, @npm.id, 'b')
  end

  test "different hosts have independent buckets" do
    other = Registry.create!(name: 'other', url: 'https://other.example.org', ecosystem: 'npm', rate_limit: 2)
    refute @strategy.throttled?(SecureRandom.hex, @npm.id, 'a')
    refute @strategy.throttled?(SecureRandom.hex, @npm.id, 'b')
    refute @strategy.throttled?(SecureRandom.hex, other.id, 'a')
    refute @strategy.throttled?(SecureRandom.hex, other.id, 'b')
    assert @strategy.throttled?(SecureRandom.hex, @npm.id, 'c')
    assert @strategy.throttled?(SecureRandom.hex, other.id, 'c')
  end
end
