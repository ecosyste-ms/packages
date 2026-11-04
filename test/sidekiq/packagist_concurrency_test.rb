require 'test_helper'
require 'rake'
require 'timeout'

class PackagistConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @threads = []
    @entered = Queue.new
    @release = Queue.new
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    @time = Time.current.change(usec: 0)
    suffix = SecureRandom.hex(6)
    @registry = Registry.create!(name: "packagist-#{suffix}", url: "https://packagist.org/#{suffix}", ecosystem: 'Packagist',
      metadata: {'packagist_malware' => {'packages' => {}}})
    @first = create_package("concurrency-#{suffix}/first")
    @second = create_package("concurrency-#{suffix}/second")
    @env_keys = %w[REGISTRY RUN DRY_RUN LIMIT MAX_SECONDS PAUSE FROM_ID TO_ID NAME]
    @environment = @env_keys.to_h { |key| [key, ENV[key]] }
    Rails.application.load_tasks unless Rake::Task.task_defined?('packages:cleanup_packagist')
  end

  teardown do
    @threads.size.times { @release << true }
    @threads.each do |thread|
      begin
        thread.join(10)
      rescue StandardError, SystemExit
      ensure
        thread.kill.join if thread.alive?
      end
    end
    ActiveSupport::Notifications.unsubscribe(@subscriber) if @subscriber
    @environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    REDIS.del("registry_cleanup:#{@registry.id}")
    @registry.packages.each(&:destroy!)
    @registry.maintainers.each(&:destroy!)
    @registry.destroy!
  end

  %w[sync versions malware removal cleanup].each do |path|
    test "#{path} allows another package to finish while its writes are uncommitted" do
      configure(path)
      pause_after_write
      first = start_worker(:held) { perform(path, @first) }
      wait_for_write

      second = start_worker(:other) { perform('sync', @second) }
      finish(second)

      assert_equal '2.0.0', @second.reload.latest_release_number
      assert_nil @first.reload.last_synced_at
      @release << true
      finish(first)
      if path == 'cleanup'
        assert_equal 1, @registry.reload.metadata.dig('packagist_cleanup', 'all', 'processed')
      elsif path == 'removal'
        assert_equal 'removed', @first.reload[:status]
      elsif path == 'malware'
        assert_equal 'malware', @first.versions.find_by!(number: '1.0.0').status
      else
        assert_equal '2.0.0', @first.reload.latest_release_number
      end
    end
  end

  %w[sync versions malware removal].each do |path|
    test "#{path} waits for a concurrent sync of the same package" do
      pause_after_write
      first = start_worker(:held) { perform('sync', @first) }
      wait_for_write
      if path == 'removal'
        stub_request(:get, "https://repo.packagist.org/p2/#{@first.name}.json").to_return(status: 404)
      end
      second = start_worker(:other) { perform(path, @first) }
      wait_for_package_lock(second)

      @release << true
      finish(first)
      if path == 'malware'
        finish(second)
      else
        assert_raises(Ecosystem::Packagist::RetryableError) { finish(second) }
      end
      assert_equal '2.0.0', @first.reload.latest_release_number
      assert_nil @first.versions.find_by!(number: '2.0.0').status
    end
  end

  %w[sync versions malware cleanup].each do |path|
    test "#{path} rolls back if the malware summary changes during writes" do
      configure(path)
      LiveEvent.stubs(:enabled?).returns(true)
      LiveEvent.expects(:emit).never
      before = @first.reload.attributes
      version_before = @first.versions.first.attributes
      dependency = @first.versions.first.dependencies.create!(package_name: 'ext-json', ecosystem: 'packagist', requirements: '*')
      pause_after_write
      worker = start_worker(:held) { perform(path, @first) }
      wait_for_write

      packages = path == 'malware' ? {} : {@first.name => '1.0.0'}
      stub_request(:get, PackagistMalware::MALWARE_SUMMARY_URL)
        .to_return(body: {filter: {malware: packages}}.to_json, headers: {'ETag' => 'changed'})
      poll = start_worker(:poll) { Registry.find(@registry.id).ecosystem_instance.sync_malware_async }
      finish(poll)

      @release << true
      error = assert_raises(path == 'cleanup' ? SystemExit : Ecosystem::Packagist::RetryableError) { finish(worker) }
      assert_match(/summary changed|pending failures/, error.message)
      assert_equal before, @first.reload.attributes
      assert_equal [version_before], @first.versions.reload.map(&:attributes)
      assert Dependency.exists?(dependency.id)
      assert_equal packages, @registry.reload.metadata.dig('packagist_malware', 'packages')
      assert_nil @cache.read(['packagist', 'tagged_versions', @first.name])
      if path == 'cleanup'
        state = @registry.metadata.dig('packagist_cleanup', 'all')
        assert_equal 0, state['processed']
        assert_equal [@first.id.to_s], state['failures'].keys
        assert_nil REDIS.get("registry_cleanup:#{@registry.id}")
      end
    end
  end

  test 'a replacement cleanup waits for the expired owners writes to roll back' do
    pause_after_write
    first = start_worker(:held) { cleanup.run }
    wait_for_write
    REDIS.del("registry_cleanup:#{@registry.id}")
    second = start_worker(:other) { cleanup.run }
    wait_for_package_lock(second)

    @release << true
    assert_raises(Cleanup::Base::LockLost) { finish(first) }
    result = finish(second)

    assert_equal 1, result[:processed]
    assert_empty result[:failures]
    assert_equal '2.0.0', @first.reload.latest_release_number
    assert_equal 1, @registry.reload.metadata.dig('packagist_cleanup', 'all', 'processed')
    assert_nil REDIS.get("registry_cleanup:#{@registry.id}")
  end

  test 'concurrent imports of a new package serialize before creating its row' do
    name = @first.name
    @first.destroy!
    pause_after_write
    first = start_worker(:held) { perform('sync', @first) }
    wait_for_write
    second = start_worker(:other) { perform('sync', @first) }
    wait_for_package_lock(second)

    @release << true
    finish(first)
    assert_raises(Ecosystem::Packagist::RetryableError) { finish(second) }

    assert_equal 1, @registry.packages.where(name: name).count
    assert_equal '2.0.0', @registry.packages.find_by!(name: name).latest_release_number
  end

  %w[sync versions].each do |path|
    test "#{path} publishes events only after releasing its transaction locks" do
      LiveEvent.stubs(:enabled?).returns(true)
      events = []
      LiveEvent.stubs(:emit).with do |payload|
        events << payload
        refute Registry.connection.transaction_open?
        assert_equal '2.0.0', Package.find(@first.id).latest_release_number
        true
      end

      perform(path, @first)

      assert_not_empty events
    end
  end

  test 'a repository enqueue failure preserves the committed result and continues sync work' do
    upstream(@first, repository: 'https://example.com/library', maintainers: [{'name' => 'callback-maintainer'}])
    Package.any_instance.unstub(:update_repo_metadata_async)
    Package.any_instance.unstub(:update_dependent_repos_count_async)
    UpdateRepoMetadataWorker.expects(:perform_async).with(@first.id).raises(Redis::CannotConnectError, 'queue unavailable')
    UpdateDependentReposCountWorker.expects(:perform_async).with(@first.id)
    Rails.logger.expects(:warn).with("Packagist post-sync callback failed for packagist:#{@registry.id}:#{@first.name}: Redis::CannotConnectError: queue unavailable")
    LiveEvent.stubs(:enabled?).returns(true)
    events = []
    LiveEvent.stubs(:emit).with do |payload|
      events.concat(Array.wrap(payload))
      refute Registry.connection.transaction_open?
      true
    end

    result = SyncPackageWorker.new.perform(@registry.id, @first.name, true)

    assert_equal @first.id, result.id
    assert_equal '2.0.0', @first.reload.latest_release_number
    assert_equal %w[1.0.0 2.0.0], @first.versions.order(:number).pluck(:number)
    assert_equal ['version.created'], events.map { |event| event[:event] }
    assert_equal '2.0.0', events.first.dig(:version, 'number')
    assert_equal ['callback-maintainer'], @first.maintainers.pluck(:login)
    assert_equal 1, @first.maintainers_count
    assert_not_nil @cache.read(['packagist', 'tagged_versions', @first.name])
  end

  def create_package(name)
    package = @registry.packages.create!(name: name, ecosystem: 'packagist', status: 'active')
    package.versions.create!(number: '1.0.0', registry: @registry, licenses: 'old')
    upstream(package)
    package
  end

  def upstream(package, flags: [], repository: nil, maintainers: [])
    versions = %w[2.0.0 1.0.0].map do |number|
      {'name' => package.name, 'version' => number, 'time' => @time.iso8601, 'license' => ['MIT'],
        'require' => {'php' => '^8'}, 'dist' => {'type' => 'zip', 'url' => "https://example.com/#{number}.zip"}}
    end
    versions.each { |version| version['source'] = {'type' => 'git', 'url' => repository} } if repository
    full = {'package' => {'name' => package.name, 'description' => 'Example', 'versions' => versions.index_by { |v| v['version'] },
      'maintainers' => maintainers, 'downloads' => {'total' => 1}}}
    stub_request(:get, "https://packagist.org/packages/#{package.name}.json").to_return(body: full.to_json)
    stub_request(:get, "https://repo.packagist.org/p2/#{package.name}.json")
      .to_return(body: {packages: {package.name => versions}, filter: {malware: flags}}.to_json,
        headers: {'Last-Modified' => @time.httpdate})
  end

  def configure(path)
    if path == 'malware'
      @registry.update!(metadata: {'packagist_malware' => {'packages' => {@first.name => '1.0.0'}}})
      upstream(@first, flags: [{'constraint' => '1.0.0', 'source' => 'packagist'}])
    elsif path == 'removal'
      stub_request(:get, "https://repo.packagist.org/p2/#{@first.name}.json").to_return(status: 404)
    end
  end

  def perform(path, package)
    case path
    when 'sync'
      SyncPackageWorker.new.perform(@registry.id, package.name, true)
    when 'versions'
      UpdateVersionsWorker.new.perform(package.id)
    when 'malware'
      SyncPackagistMalwareWorker.new.perform(@registry.id, package.name)
    when 'removal'
      SyncPackagistChangeWorker.new.perform(@registry.id, {'type' => 'delete', 'package' => package.name, 'time' => @time.to_i})
    when 'cleanup'
      @env_keys.each { |key| ENV.delete(key) }
      ENV.update('REGISTRY' => @registry.name, 'NAME' => package.name, 'DRY_RUN' => 'false', 'LIMIT' => '1', 'PAUSE' => '0')
      task = Rake::Task['packages:cleanup_packagist']
      task.reenable
      task.invoke
    end
  end

  def cleanup
    Cleanup::Packagist.new(Registry.find(@registry.id), name: @first.name, dry_run: false, limit: 1, pause: 0, output: StringIO.new)
  end

  def pause_after_write
    @subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      next unless Thread.current[:role] == :held && !Thread.current[:paused]
      next unless args.last[:sql].start_with?('UPDATE "versions"')

      Thread.current[:paused] = true
      @entered << true
      @release.pop
    end
  end

  def start_worker(role, &block)
    @threads << Thread.new do
      Thread.current.report_on_exception = false
      Thread.current[:role] = role
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        Thread.current[:backend_pid] = connection.select_value('SELECT pg_backend_pid()')
        connection.execute("SET statement_timeout = '10s'")
        begin
          block.call
        ensure
          connection.execute('RESET statement_timeout')
        end
      end
    end
    @threads.last
  end

  def wait_for_write
    Timeout.timeout(10) { @entered.pop }
  end

  def wait_for_package_lock(thread)
    Timeout.timeout(5) do
      loop do
        pid = thread[:backend_pid]
        waiting = pid && Registry.uncached { Registry.connection.select_value("SELECT wait_event FROM pg_stat_activity WHERE pid = #{Integer(pid)}") }
        break if waiting == 'advisory'
        unless thread.alive?
          thread.value
          raise 'Worker finished without waiting for the package lock'
        end
        sleep 0.01
      end
    end
  end

  def finish(thread)
    raise 'Worker did not finish while the other package was paused' unless thread.join(5)
    thread.value
  end
end
