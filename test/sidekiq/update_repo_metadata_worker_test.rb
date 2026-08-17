require "test_helper"

class UpdateRepoMetadataWorkerTest < ActiveSupport::TestCase
  setup do
    @strategy = Sidekiq::Throttled::Registry.get(UpdateRepoMetadataWorker)
    @strategy.reset!
  end

  teardown do
    @strategy.reset!
  end

  test "limits concurrent repository metadata updates" do
    jids = 5.times.map { SecureRandom.hex }

    jids.each do |jid|
      refute @strategy.throttled?(jid, 1)
    end
    assert @strategy.throttled?(SecureRandom.hex, 1)

    @strategy.finalize!(jids.first, 1)
    refute @strategy.throttled?(SecureRandom.hex, 1)
  end

  test "requeues the existing unique job when throttled" do
    assert_equal :enqueue, @strategy.requeue_with
  end
end
