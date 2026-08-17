require "test_helper"

class UniqueJobOptionsTest < ActiveSupport::TestCase
  def unique_workers
    Rails.root.glob("app/sidekiq/*_worker.rb").filter_map do |path|
      worker = path.basename(".rb").to_s.camelize.constantize
      worker if worker.get_sidekiq_options["lock"]
    end
  end

  test "unique jobs have a global lock ttl" do
    assert_equal 1.hour.to_i, SidekiqUniqueJobs.config.lock_ttl
  end

  test "unique workers use the current lock ttl option" do
    assert_predicate unique_workers, :any?

    unique_workers.each do |worker|
      options = worker.get_sidekiq_options

      assert_equal 1.hour.to_i, options["lock_ttl"], worker.name
      assert_not options.key?("lock_expiration"), worker.name
    end
  end

  test "prepared unique jobs retain a positive lock ttl" do
    unique_workers.each do |worker|
      options = worker.get_sidekiq_options
      item = {
        "class" => worker.name,
        "queue" => options["queue"],
        "args" => [1]
      }

      SidekiqUniqueJobs::Job.prepare(item)

      assert_equal 1.hour.to_i, item["lock_ttl"], worker.name
    end
  end
end
