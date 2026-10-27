require 'test_helper'
require 'active_support/testing/constant_stubbing'

class ResumableDependentPackageCountsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  setup do
    @registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @target = @registry.packages.create!(name: 'target', ecosystem: 'npm', dependent_packages_count: 99)
    @consumer = @registry.packages.create!(name: 'consumer', ecosystem: 'npm')
    @version = @consumer.versions.create!(number: '1.0.0')
    @other = @registry.packages.create!(name: 'other', ecosystem: 'npm').versions.create!(number: '1.0.0')
    @worker = UpdateDependentPackagesCountWorker.new
    @recount = DependentPackageRecount.new
    REDIS.unlink(DependentPackageRecount::REDIS_KEY)
    UpdateDependentPackagesCountWorker.clear
    Sidekiq::Testing.server_middleware.add SidekiqUniqueJobs::Middleware::Server
  end

  teardown do
    Sidekiq::Testing.server_middleware.remove SidekiqUniqueJobs::Middleware::Server
    REDIS.unlink(DependentPackageRecount::REDIS_KEY)
    UpdateDependentPackagesCountWorker.clear
  end

  def dependency(version = @version, **attributes)
    version.dependencies.create!({ package_name: @target.name, package_id: @target.id,
                                   ecosystem: 'npm', requirements: '*' }.merge(attributes))
  end

  def finish
    UpdateDependentPackagesCountWorker.drain
    assert_nil @recount.state['run_id']
    @target.reload.dependent_packages_count
  end

  test 'real batch size yields after one thousand rows and publishes the distinct count at completion' do
    rows = Array.new(1000) { { version_id: @version.id, package_id: @target.id, package_name: @target.name, ecosystem: 'npm', requirements: '*' } }
    Dependency.insert_all!(rows)
    dependency(@other)
    settings = sql_settings

    @worker.perform(@target.id, true)

    assert_equal 99, @target.reload.dependent_packages_count
    assert_equal 1000, Dependency.where(package_id: @target.id).where('id <= ?', @recount.state['last_dependency_id']).count
    assert_equal [[@target.id, true]], UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'] }
    assert_equal settings, sql_settings
    assert_equal 2, finish
    assert_equal @target.dependent_packages.count, @target.dependent_packages_count
  end

  test 'deduplicates across releases and excludes missing source packages and versions' do
    dependency
    dependency(@consumer.versions.create!(number: '2.0.0'))
    dependency(@other)
    @other.package.delete
    dependency(version_id: -1)
    @worker.perform(@target.id, true)
    assert_equal 1, @target.reload.dependent_packages_count
    assert_nil @recount.state['run_id']
  end

  test 'same package resumes an active recount even without the continuation argument' do
    dependency
    dependency(@other)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      Package.any_instance.expects(:update_dependent_packages_count).never
      @worker.perform(@target.id)
      assert_equal 2, @target.reload.dependent_packages_count
    end
  end

  test 'missing redis state restarts rather than publishing a partial count' do
    dependency
    dependency(@other)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      old_run = @recount.state['run_id']
      REDIS.unlink(DependentPackageRecount::REDIS_KEY)
      UpdateDependentPackagesCountWorker.perform_one
      refute_equal old_run, @recount.state['run_id']
      assert_equal 99, @target.reload.dependent_packages_count
      assert_equal 2, finish
    end
  end

  test 'completed redis state survives a failed publication and is published on retry' do
    dependency
    Package.any_instance.stubs(:update_dependent_packages_count).raises('full recount must not run')
    relation = mock('publication')
    relation.expects(:where).with('dependent_packages_count IS DISTINCT FROM ?', 1).returns(relation)
    relation.expects(:update_all).raises(ActiveRecord::LockWaitTimeout)
    Package.stubs(:where).with(id: @target.id).returns(relation)
    @worker.perform(@target.id, true)
    assert_equal 99, @target.reload.dependent_packages_count
    assert_equal 'complete', @recount.state['status']
    assert_in_delta 1.minute.from_now.to_f, UpdateDependentPackagesCountWorker.jobs.sole['at'], 5
    Package.unstub(:where)
    assert_equal 1, finish
  end

  test 'query cancellation preserves progress and yields before retry' do
    dependency
    dependency(@other)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      before = @recount.state
      DependentPackageRecount.any_instance.stubs(:read_batch).raises(ActiveRecord::QueryCanceled)
      UpdateDependentPackagesCountWorker.perform_one
      assert_equal before, @recount.state
      assert_equal 99, @target.reload.dependent_packages_count
      assert_in_delta 1.minute.from_now.to_f, UpdateDependentPackagesCountWorker.jobs.sole['at'], 5
      DependentPackageRecount.any_instance.unstub(:read_batch)
      assert_equal 2, finish
    end
  end

  test 'another expensive target waits while ordinary counts can still finish' do
    dependency
    dependency(@other)
    second = @registry.packages.create!(name: 'second', ecosystem: 'npm', dependent_packages_count: 99)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      before = @recount.state
      @worker.perform(second.id, true)
      assert_equal before, @recount.state
      job = UpdateDependentPackagesCountWorker.jobs.find { |item| item['args'].first == second.id }
      assert_in_delta 1.minute.from_now.to_f, job['at'], 5
      @worker.perform(second.id)
      assert_equal 0, second.reload.dependent_packages_count
      assert_equal before, @recount.state
      assert_equal 2, finish
    end
  end

  test 'expired active state releases the single recount slot' do
    dependency
    dependency(@other)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      assert_operator REDIS.ttl(DependentPackageRecount::REDIS_KEY), :>, 0
      REDIS.expire(DependentPackageRecount::REDIS_KEY, 0)
      @worker.perform(@other.package_id, true)
      assert_equal 0, @other.package.reload.dependent_packages_count
      assert_equal 2, finish
    end
  end

  test 'changes behind the cursor and above the cutoff are corrected by a fresh recount' do
    earlier = dependency(@other, package_id: nil)
    dependency
    dependency
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      earlier.update_column(:package_id, @target.id)
      dependency(@other)
      assert_equal 1, finish
      @worker.perform(@target.id, true)
      assert_equal 2, finish
      assert_equal @target.dependent_packages.count, @target.dependent_packages_count
    end
  end

  test 'fresh recount removes dependents deleted during an earlier pass' do
    earlier = dependency
    dependency(@other)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      earlier.delete
      assert_equal 2, finish
      @worker.perform(@target.id, true)
      assert_equal 1, finish
    end
  end

  test 'stale checkpoints cannot advance a replacement recount' do
    dependency
    dependency(@other)
    stub_const(DependentPackageRecount, :BATCH_SIZE, 1) do
      @worker.perform(@target.id, true)
      old = @recount.state
      REDIS.unlink(DependentPackageRecount::REDIS_KEY)
      UpdateDependentPackagesCountWorker.perform_one
      assert_equal 'restart', @recount.checkpoint(old, old['upper_dependency_id'], true, [-1])
      assert_equal 2, finish
    end
  end

  test 'normal requests and continuations share a uniqueness lock' do
    job = nil
    SidekiqUniqueJobs.use_config(enabled: true) do
      jid = UpdateDependentPackagesCountWorker.perform_async(@target.id, true)
      job = UpdateDependentPackagesCountWorker.jobs.find { |item| item['jid'] == jid }
      assert job
      assert_nil UpdateDependentPackagesCountWorker.perform_async(@target.id)
    end
  ensure
    SidekiqUniqueJobs::Unlockable.unlock(job) if job
  end

  test 'missing packages and unchanged counts do not leak settings or rewrite timestamps' do
    before = sql_settings
    @worker.perform(-1, true)
    assert_equal before, sql_settings
    @target.update_column(:dependent_packages_count, 0)
    updated_at = @target.updated_at
    @worker.perform(@target.id, true)
    assert_equal updated_at, @target.reload.updated_at
    assert_equal before, sql_settings
  end

  def sql_settings
    %w[statement_timeout lock_timeout max_parallel_workers_per_gather].to_h do |name|
      [name, Package.connection.select_value("SHOW #{name}")]
    end
  end
end
