require "test_helper"

class CleanLegacyUniqueJobLocksWorkerTest < ActiveSupport::TestCase
  setup do
    @cleanup = mock
    LegacyUniqueJobLocks.stubs(:new).with(
      apply: true,
      scan_count: LegacyUniqueJobLocks::MAX_SCAN_COUNT
    ).returns(@cleanup)
    Sidekiq.logger.stubs(:info)
  end

  test "schedules the next batch when the scan is incomplete" do
    @cleanup.expects(:call).returns(complete: false)
    CleanLegacyUniqueJobLocksWorker.expects(:perform_in).with(1.minute)

    CleanLegacyUniqueJobLocksWorker.new.perform
  end

  test "stops when the scan is complete" do
    @cleanup.expects(:call).returns(complete: true)
    CleanLegacyUniqueJobLocksWorker.expects(:perform_in).never

    CleanLegacyUniqueJobLocksWorker.new.perform
  end
end
