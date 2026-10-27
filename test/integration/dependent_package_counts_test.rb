require 'test_helper'

class DependentPackageCountsTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    UpdateDependentPackagesCountWorker.clear
    REDIS.unlink(DependentPackageRecount::REDIS_KEY)
    Sidekiq::Testing.server_middleware.add SidekiqUniqueJobs::Middleware::Server
  end

  teardown do
    Sidekiq::Testing.server_middleware.remove SidekiqUniqueJobs::Middleware::Server
    UpdateDependentPackagesCountWorker.clear
    REDIS.unlink(DependentPackageRecount::REDIS_KEY)
  end

  test 'sync links incoming dependencies and queues a historical count without repository work' do
    sync_npm('vatrix', { '1.0.0' => {} })
    target = @registry.packages.find_by!(name: 'vatrix')
    sync_npm('consumer', { '1.0.0' => { 'vatrix' => '^1.0.0' }, '2.0.0' => {} })

    dependency = Dependency.find_by!(package_name: 'vatrix')
    assert_equal target.id, dependency.package_id
    assert_equal [[target.id]], UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'] }
    assert_in_delta 10.minutes.from_now.to_f, UpdateDependentPackagesCountWorker.jobs.first['at'], 5
    Package.any_instance.expects(:fetch_dependent_repos_count).never
    Package.any_instance.expects(:update_top_dependent_packages).never
    Package.any_instance.expects(:update_rankings).never
    UpdateDependentPackagesCountWorker.drain
    assert_equal 1, target.reload.dependent_packages_count

    get dependent_packages_api_v1_registry_package_path(registry_id: @registry.name, id: target.name)
    assert_response :success
    assert_empty JSON.parse(response.body)
    get dependent_packages_api_v1_registry_package_path(registry_id: @registry.name, id: target.name, latest: 'false')
    assert_response :success
    assert_equal ['consumer'], JSON.parse(response.body).map { |row| row.fetch('name') }

    get dependent_packages_registry_package_path(registry_id: @registry.name, id: target.name)
    assert_response :success
    assert_select 'p', text: /count includes all releases.*latest releases only/
  end

  test 'count worker excludes missing source packages and counts existing packages once across releases' do
    sync_npm('vatrix', { '1.0.0' => {} })
    sync_npm('consumer', { '1.0.0' => { 'vatrix' => '*' }, '2.0.0' => { 'vatrix' => '*' } })
    sync_npm('orphan', { '1.0.0' => { 'vatrix' => '*' } })
    @registry.packages.find_by!(name: 'orphan').delete
    @registry.packages.find_by!(name: 'consumer').update_column(:status, 'removed')
    target = @registry.packages.find_by!(name: 'vatrix')
    target.update_column(:dependent_packages_count, 99)

    UpdateDependentPackagesCountWorker.new.perform(target.id)

    assert_equal 1, target.reload.dependent_packages_count
    get dependent_packages_api_v1_registry_package_path(registry_id: @registry.name, id: target.name, latest: 'false')
    assert_equal ['consumer'], JSON.parse(response.body).map { |row| row.fetch('name') }
  end

  test 'worker restores SQL settings and does not rewrite an unchanged count' do
    target = @registry.packages.create!(name: 'vatrix', ecosystem: 'npm')
    original_updated_at = target.updated_at
    settings = sql_settings
    UpdateDependentPackagesCountWorker.new.perform(target.id)
    assert_equal settings, sql_settings
    assert_equal original_updated_at, target.reload.updated_at
    UpdateDependentPackagesCountWorker.new.perform(-1)
    assert_equal settings, sql_settings
  end

  test 'dependency counts are queued even when the ecosystem has no repository counts' do
    Ecosystem::Npm.any_instance.stubs(:has_dependent_repos?).returns(false)
    sync_npm('vatrix', { '1.0.0' => {} })
    target = @registry.packages.find_by!(name: 'vatrix')
    sync_npm('consumer', { '1.0.0' => { 'vatrix' => '*' } })
    UpdateDependentPackagesCountWorker.drain
    assert_equal 1, target.reload.dependent_packages_count
  end

  test 'query cancellation preserves the count and cached response and schedules a batched recount' do
    target = @registry.packages.create!(name: 'vatrix', ecosystem: 'npm', dependent_packages_count: 99)
    target.top_dependent_packages.create!(sort: 'downloads', dependent_ids: [])
    settings = sql_settings
    slow_scope = Object.new
    slow_scope.define_singleton_method(:count) do
      raise 'Missing query timeout' unless Package.connection.select_value('SHOW statement_timeout') == '2s'
      Package.connection.execute("SET LOCAL statement_timeout = '1ms'")
      Package.connection.select_value('SELECT count(*) FROM pg_sleep(0.02)')
    end
    Package.any_instance.stubs(:dependent_packages).returns(slow_scope)
    SidekiqUniqueJobs.use_config(enabled: true) do
      UpdateDependentPackagesCountWorker.perform_async(target.id)
      UpdateDependentPackagesCountWorker.perform_one
      assert_nil UpdateDependentPackagesCountWorker.perform_async(target.id)
    end
    assert_equal 99, target.reload.dependent_packages_count
    assert_equal settings, sql_settings
    assert_equal 1, target.top_dependent_packages.reload.count
    job = UpdateDependentPackagesCountWorker.jobs.sole
    assert_equal [target.id, true], job['args']
    assert_in_delta 1.minute.from_now.to_f, job['at'], 5
  end

  test 'recounts preserve sorted caches until their separate refresh runs' do
    sync_npm('vatrix', { '1.0.0' => {} })
    sync_npm('consumer', { '1.0.0' => { 'vatrix' => '*' } })
    UpdateDependentPackagesCountWorker.drain
    target = @registry.packages.find_by!(name: 'vatrix')
    consumer = @registry.packages.find_by!(name: 'consumer')
    target.top_dependent_packages.create!(sort: 'downloads', dependent_ids: [consumer.id])

    sync_npm('consumer', { '1.0.0' => { 'vatrix' => '*' }, '2.0.0' => {} })
    assert_equal [[target.id]], UpdateDependentPackagesCountWorker.jobs.map { |job| job['args'] }
    UpdateDependentPackagesCountWorker.drain

    assert_equal 1, target.reload.dependent_packages_count
    get dependent_packages_api_v1_registry_package_path(registry_id: @registry.name, id: target.name, sort: 'downloads')
    assert_response :success
    assert_equal ['consumer'], JSON.parse(response.body).map { |row| row.fetch('name') }
    assert_equal 'top_dependent_packages', response.headers['X-Source']
  end

  test 'PyPI sync accepts a canonical package despite ambiguous legacy aliases' do
    registry = Registry.create!(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    %w[foo_bar foo.bar].each do |name|
      registry.packages.create!(name: name, ecosystem: 'pypi', metadata: { normalized_name: 'foo-bar' })
    end
    metadata = { info: { name: 'foo-bar', version: '1.0.0', summary: 'Example', requires_dist: [] }, releases: {} }
    stub_request(:get, 'https://pypi.org/pypi/foo-bar/json').to_return(status: 200, body: metadata.to_json)
    stub_request(:get, 'https://pypi.org/pypi/foo-bar/1.0.0/json').to_return(status: 200, body: metadata.to_json)
    stub_request(:get, 'https://pypistats.org/api/packages/foo-bar/recent').to_return(status: 200, body: { data: { last_month: 1 } }.to_json)
    SyncPackageWorker.new.perform(registry.id, 'foo-bar', true)
    assert registry.packages.exists?(name: 'foo-bar')
    assert_equal 3, registry.packages.count
  end

  def sql_settings
    %w[statement_timeout lock_timeout max_parallel_workers_per_gather].to_h do |name|
      [name, Package.connection.select_value("SHOW #{name}")]
    end
  end

  def sync_npm(name, releases)
    metadata = {
      '_id' => name, 'maintainers' => [], 'dist-tags' => { 'latest' => releases.keys.last },
      'versions' => releases.to_h do |number, dependencies|
        [number, { 'name' => name, 'version' => number, 'license' => 'MIT', 'dependencies' => dependencies }]
      end,
      'time' => releases.keys.to_h { |number| [number, '2024-01-01T00:00:00Z'] }
    }
    stub_request(:get, "https://registry.npmjs.org/#{name}").to_return(status: 200, body: metadata.to_json)
    stub_request(:get, "https://api.npmjs.org/downloads/point/last-month/#{name}").to_return(status: 200, body: { downloads: 100 }.to_json)
    SyncPackageWorker.new.perform(@registry.id, name, true)
  end
end
