require "test_helper"

class LegacyUniqueJobLocksTest < ActiveSupport::TestCase
  setup do
    @redis = mock
    @digests = mock
    @expiring_digests = mock
    @deleter = mock
  end

  test "audit compares primary lock keys with the digest index" do
    scan = mock
    scan.expects(:count).returns(120)
    @redis.expects(:scan).with(
      "MATCH",
      LegacyUniqueJobLocks::PRIMARY_LOCK_PATTERN,
      "COUNT",
      LegacyUniqueJobLocks::AUDIT_SCAN_COUNT
    ).returns(scan)
    @digests.expects(:page).with(page_size: 1).returns([5, 0, []])
    @expiring_digests.expects(:page).with(page_size: 1).returns([2, 0, []])

    result = LegacyUniqueJobLocks.audit(
      redis: @redis,
      digests: @digests,
      expiring_digests: @expiring_digests
    )

    assert_equal({ primary: 120, indexed: 7, unindexed_estimate: 113 }, result)
  end

  test "dry run reports only unindexed permanent locks without live jobs" do
    orphan = "uniquejobs:#{'a' * 32}"
    expiring = "uniquejobs:#{'b' * 32}"
    indexed = "uniquejobs:#{'c' * 32}"
    live = "uniquejobs:#{'d' * 32}"
    expiring_indexed = "uniquejobs:#{'e' * 32}"
    pipeline = mock

    @redis.expects(:get).with(LegacyUniqueJobLocks::AUDIT_CURSOR_KEY).returns("12")
    @redis.expects(:call).with(
      "SCAN",
      "12",
      "MATCH",
      LegacyUniqueJobLocks::PRIMARY_LOCK_PATTERN,
      "COUNT",
      1_000
    ).returns(["42", [orphan, expiring, indexed, live, expiring_indexed]])
    [orphan, expiring, indexed, live, expiring_indexed].each do |digest|
      pipeline.expects(:pttl).with(digest)
      pipeline.expects(:zscore).with(SidekiqUniqueJobs::DIGESTS, digest)
      pipeline.expects(:zscore).with(SidekiqUniqueJobs::EXPIRING_DIGESTS, digest)
    end
    @redis.expects(:pipelined).yields(pipeline).returns([
      -1, nil, nil,
      5_000, nil, nil,
      -1, "123", nil,
      -1, nil, nil,
      -1, nil, "456"
    ])
    @redis.expects(:set).with(LegacyUniqueJobLocks::AUDIT_CURSOR_KEY, "42")
    @deleter.expects(:call).never

    result = LegacyUniqueJobLocks.new(
      redis: @redis,
      live_digests: Set[live],
      deleter: @deleter,
      scan_count: 1_000
    ).call

    assert_equal 5, result[:scanned]
    assert_equal 1, result[:candidates]
    assert_equal 0, result[:deleted]
    assert_equal [orphan], result[:sample]
    assert_equal "42", result[:next_cursor]
    assert_not result[:complete]
  end

  test "apply deletes a bounded batch and uses a separate cursor" do
    orphan = "uniquejobs:#{'a' * 32}"
    pipeline = mock

    @redis.expects(:get).with(LegacyUniqueJobLocks::CLEANUP_CURSOR_KEY).returns(nil)
    @redis.expects(:call).with(
      "SCAN",
      "0",
      "MATCH",
      LegacyUniqueJobLocks::PRIMARY_LOCK_PATTERN,
      "COUNT",
      LegacyUniqueJobLocks::DEFAULT_SCAN_COUNT
    ).returns(["8", [orphan]])
    pipeline.expects(:pttl).with(orphan)
    pipeline.expects(:zscore).with(SidekiqUniqueJobs::DIGESTS, orphan)
    pipeline.expects(:zscore).with(SidekiqUniqueJobs::EXPIRING_DIGESTS, orphan)
    @redis.expects(:pipelined).yields(pipeline).returns([-1, nil, nil])
    @deleter.expects(:call).with([orphan], @redis).returns(1)
    @redis.expects(:set).with(LegacyUniqueJobLocks::CLEANUP_CURSOR_KEY, "8")

    result = LegacyUniqueJobLocks.new(
      redis: @redis,
      live_digests: Set.new,
      deleter: @deleter,
      apply: true
    ).call

    assert_equal 1, result[:deleted]
    assert_equal [orphan], result[:sample]
  end

  test "live digests include queued scheduled retry and active jobs" do
    queue = [stub(item: { "lock_digest" => "queued" })]
    scheduled = [stub(item: { "unique_digest" => "scheduled" })]
    retried = [stub(item: { "lock_digest" => "retried" })]
    active_job = stub(item: { "lock_digest" => "active:RUN" })
    work = stub(job: active_job)

    Sidekiq::Queue.stubs(:all).returns([queue])
    Sidekiq::ScheduledSet.stubs(:new).returns(scheduled)
    Sidekiq::RetrySet.stubs(:new).returns(retried)
    Sidekiq::WorkSet.stubs(:new).returns([["process", "thread", work]])

    assert_equal Set["queued", "scheduled", "retried", "active"], LegacyUniqueJobLocks.live_digests
  end

  test "live digest scan stops at its safety limit" do
    queue = [stub(item: {}), stub(item: {})]

    Sidekiq::ScheduledSet.stubs(:new).returns([])
    Sidekiq::RetrySet.stubs(:new).returns([])
    Sidekiq::Queue.stubs(:all).returns([queue])
    Sidekiq::WorkSet.stubs(:new).returns([])

    assert_raises(LegacyUniqueJobLocks::TooManyLiveJobs) do
      LegacyUniqueJobLocks.live_digests(max_jobs: 1)
    end
  end

  test "batch without permanent unindexed locks skips the live job scan" do
    expiring = "uniquejobs:#{'a' * 32}"
    pipeline = mock

    @redis.expects(:get).with(LegacyUniqueJobLocks::AUDIT_CURSOR_KEY).returns(nil)
    @redis.expects(:call).with(
      "SCAN",
      "0",
      "MATCH",
      LegacyUniqueJobLocks::PRIMARY_LOCK_PATTERN,
      "COUNT",
      LegacyUniqueJobLocks::DEFAULT_SCAN_COUNT
    ).returns(["0", [expiring]])
    pipeline.expects(:pttl).with(expiring)
    pipeline.expects(:zscore).with(SidekiqUniqueJobs::DIGESTS, expiring)
    pipeline.expects(:zscore).with(SidekiqUniqueJobs::EXPIRING_DIGESTS, expiring)
    @redis.expects(:pipelined).yields(pipeline).returns([5_000, nil, nil])
    @redis.expects(:set).with(LegacyUniqueJobLocks::AUDIT_CURSOR_KEY, "0")
    LegacyUniqueJobLocks.expects(:live_digests).never

    result = LegacyUniqueJobLocks.new(redis: @redis).call

    assert_equal 0, result[:candidates]
    assert result[:complete]
  end

  test "scan results are capped even when Redis returns more than COUNT" do
    keys = %w[a b c].map { |letter| "uniquejobs:#{letter * 32}" }
    pipeline = mock

    @redis.expects(:get).with(LegacyUniqueJobLocks::AUDIT_CURSOR_KEY).returns(nil)
    @redis.expects(:call).with(
      "SCAN",
      "0",
      "MATCH",
      LegacyUniqueJobLocks::PRIMARY_LOCK_PATTERN,
      "COUNT",
      2
    ).returns(["0", keys])
    keys.first(2).each do |digest|
      pipeline.expects(:pttl).with(digest)
      pipeline.expects(:zscore).with(SidekiqUniqueJobs::DIGESTS, digest)
      pipeline.expects(:zscore).with(SidekiqUniqueJobs::EXPIRING_DIGESTS, digest)
    end
    @redis.expects(:pipelined).yields(pipeline).returns([-1, nil, nil, -1, nil, nil])
    @redis.expects(:set).with(LegacyUniqueJobLocks::AUDIT_CURSOR_KEY, "0")

    result = LegacyUniqueJobLocks.new(
      redis: @redis,
      live_digests: Set.new,
      scan_count: 2
    ).call

    assert_equal 2, result[:scanned]
    assert_equal 3, result[:matched]
    assert_equal 1, result[:overflow]
    assert_not result[:complete]
  end
end
