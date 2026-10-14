require "test_helper"

class UniqueJobOptionsTest < ActiveSupport::TestCase
  def unique_workers
    Rails.root.glob("app/sidekiq/*_worker.rb").filter_map do |path|
      worker = path.basename(".rb").to_s.camelize.constantize
      worker if worker.get_sidekiq_options["lock"]
    end
  end

  def throttled_unique_workers
    unique_workers.select { |worker| worker.ancestors.include?(Sidekiq::Throttled::Job) }
  end

  test "unique jobs have a global lock ttl" do
    assert_equal 1.hour.to_i, SidekiqUniqueJobs.config.lock_ttl
  end

  test "unique workers use the current lock ttl option" do
    assert_predicate unique_workers, :any?

    unique_workers.each do |worker|
      options = worker.get_sidekiq_options

      assert_not options.key?("lock_expiration"), worker.name
    end
  end

  test "throttled unique workers keep their locks while requeued" do
    assert_predicate throttled_unique_workers, :any?

    throttled_unique_workers.each do |worker|
      assert_equal 1.day.to_i, worker.get_sidekiq_options["lock_ttl"], worker.name
    end
  end

  test "other unique workers use the global lock ttl" do
    (unique_workers - throttled_unique_workers).each do |worker|
      assert_equal SidekiqUniqueJobs.config.lock_ttl, worker.get_sidekiq_options["lock_ttl"], worker.name
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

      assert_equal options["lock_ttl"], item["lock_ttl"], worker.name
    end
  end
end
