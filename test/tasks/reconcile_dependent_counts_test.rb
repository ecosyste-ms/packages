require 'test_helper'
require 'rake'
require 'active_support/testing/constant_stubbing'

class ReconcileDependentCountsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  setup do
    @original_options = ReconcileDependentPackageCountsWorker.get_sidekiq_options.dup
    ReconcileDependentPackageCountsWorker.sidekiq_options lock_prefix: "test:reconcile:#{SecureRandom.hex}"
    Sidekiq::Testing.server_middleware.add SidekiqUniqueJobs::Middleware::Server
    silence_warnings { Rails.application.load_tasks } unless Rake::Task.task_defined?('packages:reconcile_dependent_counts')
    @registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @packages = 3.times.map { |i| @registry.packages.create!(name: "package-#{i}", ecosystem: 'npm', dependent_packages_count: 99) }
    @worker = ReconcileDependentPackageCountsWorker.new
    @queue = mock('count queue')
    @queue.stubs(:size).returns(0)
    Sidekiq::Queue.stubs(:new).with('dependent_counts').returns(@queue)
    REDIS.del(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    REDIS.unlink(DependentPackageRecount::REDIS_KEY)
    UpdateDependentPackagesCountWorker.clear
    ReconcileDependentPackageCountsWorker.clear
  end

  teardown do
    ReconcileDependentPackageCountsWorker.jobs.each { |job| SidekiqUniqueJobs::Unlockable.unlock(job) }
    UpdateDependentPackagesCountWorker.jobs.each { |job| SidekiqUniqueJobs::Unlockable.unlock(job) }
    ReconcileDependentPackageCountsWorker.get_sidekiq_options.replace(@original_options)
    Sidekiq::Testing.server_middleware.remove SidekiqUniqueJobs::Middleware::Server
    REDIS.del(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    REDIS.unlink(DependentPackageRecount::REDIS_KEY)
    UpdateDependentPackagesCountWorker.clear
    ReconcileDependentPackageCountsWorker.clear
  end

  test 'rake entrypoint starts a sweep that counts packages and repeats after completing a pass' do
    task = Rake::Task['packages:reconcile_dependent_counts']
    task.reenable
    output, = capture_io { task.invoke }
    assert_match 'Scheduled dependent count reconciliation', output
    ReconcileDependentPackageCountsWorker.perform_one
    assert_equal @packages.map(&:id), UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'].first }
    assert_equal @packages.last.id.to_s, REDIS.get(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    assert_in_delta 10.seconds.from_now.to_f, ReconcileDependentPackageCountsWorker.jobs.sole['at'], 5
    UpdateDependentPackagesCountWorker.drain
    assert_equal [0, 0, 0], @packages.map { |package| package.reload.dependent_packages_count }
    ReconcileDependentPackageCountsWorker.perform_one
    assert_equal '0', REDIS.get(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    assert_in_delta 1.day.from_now.to_f, ReconcileDependentPackageCountsWorker.jobs.sole['at'], 5
  end

  test 'sweep fills only available queue capacity and resumes at its saved package id' do
    stub_const(ReconcileDependentPackageCountsWorker, :MAX_QUEUED_JOBS, 2) do
      @queue.stubs(:size).returns(1)
      @worker.perform
      assert_equal [[@packages.first.id]], UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'] }
      @queue.stubs(:size).returns(0)
      ReconcileDependentPackageCountsWorker.perform_one
      assert_equal @packages.map(&:id), UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'].first }
      assert_equal @packages.last.id.to_s, REDIS.get(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    end
  end

  test 'full queue pauses without moving the cursor or querying packages' do
    @queue.stubs(:size).returns(ReconcileDependentPackageCountsWorker::MAX_QUEUED_JOBS)
    Package.expects(:where).never
    @worker.perform
    assert_empty UpdateDependentPackagesCountWorker.jobs
    assert_nil REDIS.get(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    assert_in_delta 1.minute.from_now.to_f, ReconcileDependentPackageCountsWorker.jobs.sole['at'], 5
  end

  test 'failed enqueue leaves the cursor unchanged so the page is retried' do
    UpdateDependentPackagesCountWorker.stubs(:perform_bulk).raises(Redis::CannotConnectError)
    assert_raises(Redis::CannotConnectError) { @worker.perform }
    assert_nil REDIS.get(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    UpdateDependentPackagesCountWorker.unstub(:perform_bulk)
    @worker.perform
    assert_equal @packages.map(&:id), UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'].first }
  end

  test 'lost cursor safely repeats packages on the next scheduled sweep' do
    @worker.perform
    UpdateDependentPackagesCountWorker.clear
    REDIS.del(ReconcileDependentPackageCountsWorker::CURSOR_KEY)
    ReconcileDependentPackageCountsWorker.perform_one
    assert_equal @packages.map(&:id), UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'].first }
  end

  test 'periodic trigger restarts a lost executing job from its saved cursor without duplicating pending work' do
    schedule = JSON.parse(Rails.root.join('app.json').read).fetch('cron').find do |entry|
      entry['command'] == 'bundle exec rake packages:reconcile_dependent_counts'
    end
    assert_equal '*/5 * * * *', schedule.fetch('schedule')
    task = Rake::Task['packages:reconcile_dependent_counts']
    2.times do
      task.reenable
      capture_io { task.invoke }
    end
    assert_equal 1, ReconcileDependentPackageCountsWorker.jobs.length
    lost_job = ReconcileDependentPackageCountsWorker.jobs.shift
    SidekiqUniqueJobs::Unlockable.unlock(lost_job)
    REDIS.set(ReconcileDependentPackageCountsWorker::CURSOR_KEY, @packages.first.id)
    task.reenable
    capture_io { task.invoke }
    ReconcileDependentPackageCountsWorker.perform_one
    assert_equal @packages.drop(1).map(&:id), UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'].first }
  end
end
