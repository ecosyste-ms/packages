require "test_helper"
require "rake"

class SidekiqUniqueJobsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sidekiq:unique_jobs:list")
    @digests = SidekiqUniqueJobs::Digests.new
  end

  test "list task runs without error" do
    assert_nothing_raised do
      capture_io { Rake::Task["sidekiq:unique_jobs:list"].execute }
    end
  end

  test "clear task runs without error" do
    assert_nothing_raised do
      capture_io { Rake::Task["sidekiq:unique_jobs:clear"].execute }
    end
  end

  test "clear_matching task aborts without PATTERN" do
    assert_raises(SystemExit) do
      capture_io { Rake::Task["sidekiq:unique_jobs:clear_matching"].execute }
    end
  end

  test "clear_matching task runs with PATTERN" do
    ENV["PATTERN"] = "*"
    assert_nothing_raised do
      capture_io { Rake::Task["sidekiq:unique_jobs:clear_matching"].execute }
    end
  ensure
    ENV.delete("PATTERN")
  end

  test "audit_locks reports indexed and unindexed lock counts" do
    result = { primary: 120, indexed: 5, unindexed_estimate: 115 }
    LegacyUniqueJobLocks.expects(:audit).returns(result)

    output, = capture_io { Rake::Task["sidekiq:unique_jobs:audit_locks"].execute }

    assert_equal result.stringify_keys, JSON.parse(output)
  end

  test "clean_legacy_locks is a bounded dry run by default" do
    cleanup = mock
    result = { cursor: "0", next_cursor: "42", scanned: 1_000, candidates: 900, deleted: 0 }
    LegacyUniqueJobLocks.expects(:new).with(
      apply: false,
      scan_count: LegacyUniqueJobLocks::DEFAULT_SCAN_COUNT
    ).returns(cleanup)
    cleanup.expects(:call).returns(result)

    output, = capture_io { Rake::Task["sidekiq:unique_jobs:clean_legacy_locks"].execute }

    assert_equal result.stringify_keys, JSON.parse(output)
  end

  test "clean_legacy_locks applies an explicit batch size" do
    ENV["APPLY"] = "true"
    ENV["COUNT"] = "2500"
    cleanup = mock
    result = { cursor: "42", next_cursor: "81", scanned: 2_500, candidates: 2_000, deleted: 2_000 }
    LegacyUniqueJobLocks.expects(:new).with(apply: true, scan_count: 2_500).returns(cleanup)
    cleanup.expects(:call).returns(result)

    output, = capture_io { Rake::Task["sidekiq:unique_jobs:clean_legacy_locks"].execute }

    assert_equal result.stringify_keys, JSON.parse(output)
  ensure
    ENV.delete("APPLY")
    ENV.delete("COUNT")
  end
end
