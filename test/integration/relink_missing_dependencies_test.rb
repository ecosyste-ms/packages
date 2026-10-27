require 'test_helper'
require 'rake'
require 'active_support/testing/constant_stubbing'

class RelinkMissingDependenciesTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  setup do
    @original_options = RelinkDependenciesWorker.get_sidekiq_options.dup
    RelinkDependenciesWorker.sidekiq_options lock_prefix: "test:relink:#{SecureRandom.hex}"
    Sidekiq::Testing.server_middleware.add SidekiqUniqueJobs::Middleware::Server
    silence_warnings { Rails.application.load_tasks } unless Rake::Task.task_defined?('packages:relink_missing_dependencies')
    @registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @version = @registry.packages.create!(name: 'consumer', ecosystem: 'npm').versions.create!(number: '1.0.0')
    @queue = mock('counts queue')
    @queue.stubs(:size).returns(0)
    Sidekiq::Queue.stubs(:new).with('dependent_counts').returns(@queue)
    REDIS.unlink(RelinkDependenciesWorker::PROGRESS_KEY, DependentPackageRecount::REDIS_KEY)
    RelinkDependenciesWorker.clear
    UpdateDependentPackagesCountWorker.clear
  end

  teardown do
    RelinkDependenciesWorker.jobs.each { |job| SidekiqUniqueJobs::Unlockable.unlock(job) }
    UpdateDependentPackagesCountWorker.jobs.each { |job| SidekiqUniqueJobs::Unlockable.unlock(job) }
    RelinkDependenciesWorker.get_sidekiq_options.replace(@original_options)
    Sidekiq::Testing.server_middleware.remove SidekiqUniqueJobs::Middleware::Server
    REDIS.unlink(RelinkDependenciesWorker::PROGRESS_KEY, DependentPackageRecount::REDIS_KEY)
    RelinkDependenciesWorker.clear
    UpdateDependentPackagesCountWorker.clear
  end

  def dependency(version = @version, **attributes)
    version.dependencies.create!({ package_name: 'late-target', ecosystem: 'npm', requirements: '*' }.merge(attributes))
  end

  def target(registry = @registry, name: 'late-target')
    registry.packages.create!(name: name, ecosystem: registry.ecosystem, dependent_packages_count: 99)
  end

  def trigger
    task = Rake::Task['packages:relink_missing_dependencies']
    task.reenable
    capture_io { task.invoke }
  end

  test 'syncing a target after its consumer schedules repair and updates the published count' do
    sync_npm('early-consumer', { 'late-target' => '*' })
    row = Dependency.find_by!(package_name: 'late-target')
    assert_nil row.package_id
    lost_job = RelinkDependenciesWorker.jobs.shift
    SidekiqUniqueJobs::Unlockable.unlock(lost_job)
    sync_npm('late-target', {})
    assert_equal 1, RelinkDependenciesWorker.jobs.length
    RelinkDependenciesWorker.perform_one
    package = @registry.packages.find_by!(name: 'late-target')
    assert_equal package.id, row.reload.package_id
    UpdateDependentPackagesCountWorker.drain
    assert_equal 1, package.reload.dependent_packages_count
    assert_equal package.dependent_packages.count, package.dependent_packages_count
  end

  test 'primary key pages advance through linked and unrelated rows before repairing a match' do
    package = target
    first = dependency(package_id: package.id)
    unmatched = dependency(package_name: 'missing')
    matched = dependency
    stub_const(ReconcileDependentPackageCountsWorker, :MAX_QUEUED_JOBS, 1) do
      trigger
      RelinkDependenciesWorker.perform_one
      assert_equal first.id.to_s, REDIS.hget(RelinkDependenciesWorker::PROGRESS_KEY, 'last_dependency_id')
      assert_nil matched.reload.package_id
      RelinkDependenciesWorker.perform_one
      assert_equal unmatched.id.to_s, REDIS.hget(RelinkDependenciesWorker::PROGRESS_KEY, 'last_dependency_id')
      RelinkDependenciesWorker.perform_one
      assert_equal package.id, matched.reload.package_id
      assert_equal 0, REDIS.exists(RelinkDependenciesWorker::PROGRESS_KEY)
      assert_in_delta 1.hour.from_now.to_f, RelinkDependenciesWorker.jobs.sole['at'], 5
      UpdateDependentPackagesCountWorker.drain
      assert_equal 1, package.reload.dependent_packages_count
    end
  end

  test 'repair resolves canonical names within the source registry and ignores orphans and other ecosystems' do
    pypi = Registry.create!(name: 'PyPI.org', url: 'https://pypi.org', ecosystem: 'pypi')
    py_version = pypi.packages.create!(name: 'consumer', ecosystem: 'pypi').versions.create!(number: '1.0.0')
    canonical = target(pypi, name: 'some-project')
    pypi.packages.create!(name: 'some_project', ecosystem: 'pypi', metadata: { normalized_name: 'some-project' })
    target(@registry, name: 'some-project')
    row = dependency(py_version, package_name: 'Some.Project', ecosystem: 'PyPI')
    foreign = dependency(package_name: 'Some.Project', ecosystem: 'pypi')
    orphan = dependency(version_id: -1)
    missing_source = @registry.packages.create!(name: 'deleted', ecosystem: 'npm')
    deleted_version = missing_source.versions.create!(number: '1.0.0')
    missing_source.delete
    orphan_source = dependency(deleted_version)
    trigger
    RelinkDependenciesWorker.perform_one
    assert_equal canonical.id, row.reload.package_id
    assert_nil foreign.reload.package_id
    assert_nil orphan.reload.package_id
    assert_nil orphan_source.reload.package_id
  end

  test 'later passes revisit unresolved dependencies and rows beyond the saved upper bound' do
    earlier = dependency
    last = dependency(package_name: 'missing')
    stub_const(ReconcileDependentPackageCountsWorker, :MAX_QUEUED_JOBS, 1) do
      trigger
      RelinkDependenciesWorker.perform_one
      assert_nil earlier.reload.package_id
      package = target
      later = dependency
      assert_equal last.id.to_s, REDIS.hget(RelinkDependenciesWorker::PROGRESS_KEY, 'upper_dependency_id')
      RelinkDependenciesWorker.perform_one
      assert_nil later.reload.package_id
      RelinkDependenciesWorker.perform_one
      assert_equal package.id, earlier.reload.package_id
      RelinkDependenciesWorker.perform_one
      RelinkDependenciesWorker.perform_one
      assert_equal package.id, later.reload.package_id
      UpdateDependentPackagesCountWorker.drain
      assert_equal 1, package.reload.dependent_packages_count
    end
  end

  test 'time budget saves progress after a registry group and resumes the next group' do
    first_target = target
    first = dependency
    other_registry = Registry.create!(name: 'mirror', url: 'https://mirror.example.org', ecosystem: 'npm')
    other_version = other_registry.packages.create!(name: 'consumer', ecosystem: 'npm').versions.create!(number: '1.0.0')
    second_target = target(other_registry)
    second = dependency(other_version)
    stub_const(Dependency, :RELINK_BATCH_SECONDS, 0) do
      trigger
      RelinkDependenciesWorker.perform_one
      assert_equal first_target.id, first.reload.package_id
      assert_nil second.reload.package_id
      assert_equal first.id.to_s, REDIS.hget(RelinkDependenciesWorker::PROGRESS_KEY, 'last_dependency_id')
      RelinkDependenciesWorker.perform_one
      assert_equal second_target.id, second.reload.package_id
    end
  end

  test 'query timeout rolls back writes and retains the cursor before retrying' do
    package = target
    row = dependency
    other_registry = Registry.create!(name: 'mirror', url: 'https://mirror.example.org', ecosystem: 'npm')
    other_version = other_registry.packages.create!(name: 'consumer', ecosystem: 'npm').versions.create!(number: '1.0.0')
    second = dependency(other_version)
    second_target = target(other_registry)
    Package.stubs(:dependency_package_ids).with(@registry.id, 'npm', ['late-target']).returns({ 'late-target' => package.id })
    Package.stubs(:dependency_package_ids).with(other_registry.id, 'npm', ['late-target']).raises(ActiveRecord::QueryCanceled)
    trigger
    RelinkDependenciesWorker.perform_one
    assert_nil row.reload.package_id
    assert_equal '0', REDIS.hget(RelinkDependenciesWorker::PROGRESS_KEY, 'last_dependency_id')
    assert_in_delta 1.minute.from_now.to_f, RelinkDependenciesWorker.jobs.sole['at'], 5
    Package.unstub(:dependency_package_ids)
    RelinkDependenciesWorker.perform_one
    assert_equal package.id, row.reload.package_id
    assert_equal second_target.id, second.reload.package_id
  end

  test 'a dependency edited after selection is not linked to the old target' do
    target
    row = dependency
    connection = Dependency.connection
    read = connection.method(:select_all)
    connection.define_singleton_method(:select_all) do |sql, *args, **kwargs|
      result = read.call(sql, *args, **kwargs)
      if sql.is_a?(String) && sql.include?('WITH page AS MATERIALIZED')
        Dependency.where(id: row.id).update_all(package_name: 'different-target')
      end
      result
    end
    trigger
    RelinkDependenciesWorker.perform_one
    assert_nil row.reload.package_id
    assert_equal 'different-target', row.package_name
    assert_empty UpdateDependentPackagesCountWorker.jobs
  ensure
    connection.singleton_class.remove_method(:select_all) if connection&.singleton_class&.instance_methods(false)&.include?(:select_all)
  end

  test 'lost progress repeats a page safely and never overwrites an existing link' do
    package = target
    first = dependency
    second = dependency
    stub_const(ReconcileDependentPackageCountsWorker, :MAX_QUEUED_JOBS, 1) do
      trigger
      RelinkDependenciesWorker.perform_one
      assert_equal package.id, first.reload.package_id
      REDIS.unlink(RelinkDependenciesWorker::PROGRESS_KEY)
      RelinkDependenciesWorker.perform_one
      assert_equal package.id, first.reload.package_id
      assert_nil second.reload.package_id
      RelinkDependenciesWorker.perform_one
      assert_equal package.id, second.reload.package_id
      UpdateDependentPackagesCountWorker.drain
      assert_equal 1, package.reload.dependent_packages_count
    end
  end

  test 'full queue pauses without advancing or querying dependencies' do
    @queue.stubs(:size).returns(ReconcileDependentPackageCountsWorker::MAX_QUEUED_JOBS)
    Dependency.expects(:maximum).never
    trigger
    RelinkDependenciesWorker.perform_one
    assert_equal 0, REDIS.exists(RelinkDependenciesWorker::PROGRESS_KEY)
    assert_in_delta 1.minute.from_now.to_f, RelinkDependenciesWorker.jobs.sole['at'], 5
  end

  test 'cron recovers a lost executing repair job without duplicating pending work' do
    schedule = JSON.parse(Rails.root.join('app.json').read).fetch('cron').find do |entry|
      entry['command'] == 'bundle exec rake packages:relink_missing_dependencies'
    end
    assert_equal '*/5 * * * *', schedule.fetch('schedule')
    row = dependency
    package = target
    2.times { trigger }
    assert_equal 1, RelinkDependenciesWorker.jobs.length
    lost_job = RelinkDependenciesWorker.jobs.shift
    SidekiqUniqueJobs::Unlockable.unlock(lost_job)
    REDIS.hset(RelinkDependenciesWorker::PROGRESS_KEY, 'last_dependency_id', 0, 'upper_dependency_id', row.id)
    trigger
    RelinkDependenciesWorker.perform_one
    assert_equal package.id, row.reload.package_id
  end

  def sync_npm(name, dependencies)
    metadata = { '_id' => name, 'maintainers' => [], 'dist-tags' => { 'latest' => '1.0.0' },
      'versions' => { '1.0.0' => { 'name' => name, 'version' => '1.0.0', 'license' => 'MIT', 'dependencies' => dependencies } },
      'time' => { '1.0.0' => '2024-01-01T00:00:00Z' } }
    stub_request(:get, "https://registry.npmjs.org/#{name}").to_return(status: 200, body: metadata.to_json)
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/#{name}").to_return(status: 200, body: { downloads: 1 }.to_json)
    SyncPackageWorker.new.perform(@registry.id, name, true)
  end
end
