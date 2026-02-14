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
end
