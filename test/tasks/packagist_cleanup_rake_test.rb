require 'test_helper'
require 'rake'

class PackagistCleanupRakeTest < ActiveSupport::TestCase
  ENV_KEYS = %w[REGISTRY RUN DRY_RUN LIMIT MAX_SECONDS PAUSE FROM_ID TO_ID NAME].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('packages:cleanup_packagist')
    @environment = ENV_KEYS.to_h { |key| [key, ENV[key]] }
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV['PAUSE'] = '0'
    @cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(@cache)
    @registry = Registry.create!(name: 'Packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist',
      metadata: {'packagist_malware' => {'packages' => {}}})
    @time = Time.current.change(usec: 0)
  end

  teardown do
    @environment.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test 'dry run previews inactive packages and platform edges without requests or writes' do
    package = create_package('vendor/library', status: 'removed')
    version = package.versions.create!(number: '1.0.0', registry: @registry, status: 'removed')
    platform = version.dependencies.create!(package_name: 'EXT-JSON', requirements: '*', ecosystem: 'Packagist', kind: 'Development')
    version.dependencies.create!(package_name: 'ext-json/package', requirements: '*', ecosystem: 'packagist', kind: 'runtime')
    before = package.reload.attributes
    registry_before = @registry.reload.attributes
    Package.any_instance.expects(:update_repo_metadata_async).never
    LiveEvent.expects(:emit).never

    writes = []
    subscriber = ->(*args) { writes << args.last[:sql] if args.last[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)\b/i) }
    output = nil
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { output = invoke }

    preview = output.find { |row| row['event'] == 'preview' }
    assert_equal package.id, preview['id']
    assert_equal 'removed', preview['status']
    assert_equal 1, preview['platform_dependencies']
    assert_equal before, package.reload.attributes
    assert_equal registry_before, @registry.reload.attributes
    assert_empty writes
    assert Dependency.exists?(platform.id)
    assert_not_requested(:get, %r{https://(repo\.)?packagist\.org/})
  end

  test 'apply repairs metadata flags withdrawals platform edges and latest selection together' do
    package = create_package('vendor/library')
    version = package.versions.create!(number: 'v1.0.0', registry: @registry, licenses: 'old',
      metadata: {'custom' => 'keep', 'provide' => {'old/virtual' => '*'}})
    withdrawn = package.versions.create!(number: '0.5.0', registry: @registry)
    real = version.dependencies.create!(package_name: 'vendor/dependency', requirements: '^2', ecosystem: 'packagist', kind: 'runtime')
    version.dependencies.create!(package_name: 'ext-json', requirements: '*', ecosystem: 'packagist', kind: 'runtime')
    withdrawn.dependencies.create!(package_name: 'PHP', requirements: '^7', ecosystem: 'Packagist', kind: 'Development')
    @registry.update!(metadata: @registry.metadata.deep_merge('packagist_malware' => {'packages' => {'vendor/library' => '2.0.0'}}))
    stable = release('1.0.0').merge('abandoned' => 'vendor/replacement')
    flagged = release('2.0.0').merge('abandoned' => 'vendor/replacement')
    upstream(package.name, [flagged, stable], malware: [{'constraint' => '2.0.0', 'source' => 'packagist', 'reason' => 'malware'}])
    LiveEvent.stubs(:enabled?).returns(true)
    LiveEvent.expects(:emit).never
    Package.any_instance.expects(:update_repo_metadata_async).never
    Package.any_instance.expects(:update_dependent_repos_count_async).never

    output = apply

    assert_equal 'abandoned', package.reload.status
    assert_equal 'vendor/replacement', package.metadata['abandoned']
    assert_equal 3, package.versions_count
    assert_equal 'v1.0.0', package.latest_release_number
    assert_equal 'MIT', version.reload.licenses
    assert_equal 'keep', version.metadata['custom']
    assert_equal stable['published-time'], version.metadata['published-time']
    assert_equal stable['source'], version.metadata['source']
    assert_equal stable['dist'].slice('type', 'url', 'reference'), version.metadata['dist']
    assert_equal({'php' => '^8', 'ext-json' => '*'}, version.metadata['platform_requirements'])
    assert_equal({'ext-xdebug' => '*'}, version.metadata['platform_requirements_dev'])
    assert_equal stable['provide'], version.metadata['provide']
    assert_equal stable['replace'], version.metadata['replace']
    assert_equal stable['conflict'], version.metadata['conflict']
    assert_equal 'removed', withdrawn.reload.status
    assert_equal 'malware', package.versions.find_by!(number: '2.0.0').status
    assert_equal [real.id], version.dependencies.pluck(:id)
    assert_empty withdrawn.dependencies
    assert_equal 2, output.last['platform_dependencies_removed']
    assert output.last['complete']
    assert_requested(:get, "https://repo.packagist.org/p2/#{package.name}.json", times: 1)
    assert_not_requested(:get, %r{~dev\.json})
  end

  test 'changed repository URLs invalidate old metadata and become eligible for scheduled refresh' do
    package = create_package('vendor/library')
    package.update!(repository_url: 'https://github.com/old/library', repo_metadata_updated_at: @time,
      repo_metadata: {'full_name' => 'old/library', 'host' => {'name' => 'GitHub'}, 'stargazers_count' => 99,
        'topics' => ['old-topic'], 'commit_stats' => {'total_committers' => 8}}, issue_metadata: {'past_year_issues_count' => 10})
    upstream(package.name)
    Package.any_instance.expects(:update_repo_metadata_async).never

    apply

    assert_equal 'https://github.com/example/library', package.reload.repository_url
    assert_empty package.repo_metadata
    assert_nil package.repo_metadata_updated_at
    assert_nil package.issue_metadata
    assert_nil package.stargazers_count
    assert_nil package.commit_stats
    assert_not_includes package.keywords, 'old-topic'
    candidates, = Package.repo_metadata_refresh_batch(after_id: package.id - 1, batch_size: 1, scan_size: 1)
    assert_equal [package.id], candidates.map(&:id)
  end

  test 'an unchanged effective repository URL preserves cached metadata despite a changed homepage' do
    package = create_package('vendor/library')
    repo_metadata = {'full_name' => 'example/library', 'host' => {'name' => 'GitHub'}, 'stargazers_count' => 99}
    issue_metadata = {'past_year_issues_count' => 10}
    package.update!(repository_url: 'https://github.com/example/library', homepage: 'https://old.example.com',
      repo_metadata: repo_metadata, repo_metadata_updated_at: @time, issue_metadata: issue_metadata)
    upstream(package.name, [release('1.0.0').merge('homepage' => 'https://new.example.com')])

    apply

    assert_equal 'https://new.example.com', package.reload.homepage
    assert_equal repo_metadata, package.repo_metadata
    assert_equal @time, package.repo_metadata_updated_at
    assert_equal issue_metadata, package.issue_metadata
  end

  test 'a changed fallback homepage invalidates repository metadata' do
    package = create_package('vendor/library')
    package.update!(homepage: 'https://old.example.com', repo_metadata: {'full_name' => 'old/library'}, repo_metadata_updated_at: @time)
    upstream(package.name, [release('1.0.0').except('source').merge('homepage' => 'https://new.example.com')])

    apply

    assert_equal 'https://new.example.com', package.reload.repository_or_homepage_url
    assert_empty package.repo_metadata
    assert_nil package.repo_metadata_updated_at
  end

  test 'removing the repository and homepage clears old repository data' do
    package = create_package('vendor/library')
    package.update!(repository_url: 'https://github.com/old/library', repo_metadata: {'full_name' => 'old/library'}, repo_metadata_updated_at: @time)
    upstream(package.name, [release('1.0.0').except('source')])

    apply

    assert_nil package.reload.repository_or_homepage_url
    assert_empty package.repo_metadata
    assert_nil package.repo_metadata_updated_at
  end

  test 'missing case-distinct packages receive malware changes only on the selected ID' do
    selected = create_package('Vendor/Library')
    other = create_package('vendor/library')
    flag = {'constraint' => '*', 'source' => 'selected', 'classification' => 'malware'}
    selected.update!(metadata: {'malware' => [flag]})
    selected_version = selected.versions.create!(number: '1.0.0', registry: @registry, metadata: {'malware' => [flag]})
    other_version = other.versions.create!(number: '1.0.0', registry: @registry)
    other_before = other.reload.attributes
    other_version_before = other_version.attributes
    ENV['FROM_ID'] = ENV['TO_ID'] = selected.id.to_s
    stub_request(:get, 'https://packagist.org/packages/Vendor/Library.json').to_return(status: 404)
    stub_request(:get, 'https://repo.packagist.org/p2/vendor/library.json').to_return(status: 404)

    output = apply

    assert output.last['complete']
    assert_equal 'removed', selected.reload.status
    assert_empty selected.metadata['malware']
    assert_equal 'removed', selected_version.reload.status
    assert_nil selected_version.metadata['malware']
    assert_equal other_before, other.reload.attributes
    assert_equal other_version_before, other_version.reload.attributes
  end

  test 'case-distinct cleanup uses the selected snapshot and retains that records malware details' do
    selected = create_package('Vendor/Library')
    other = create_package('vendor/library', status: 'removed')
    selected_flag = {'constraint' => '*', 'source' => 'selected', 'classification' => 'malware'}
    selected.update!(metadata: {'malware' => [selected_flag]})
    selected_version = selected.versions.create!(number: '1.0.0', registry: @registry)
    other.update!(metadata: {'packagist_snapshot' => {'last_modified' => (@time + 1.day).to_i, 'sha256' => 'other'},
      'packagist_removed_at' => (@time + 1.day).to_i, 'malware' => [selected_flag.merge('source' => 'other')]})
    other_version = other.versions.create!(number: '1.0.0', registry: @registry, status: 'removed')
    other_before = other.reload.attributes
    other_version_before = other_version.attributes
    @registry.update!(metadata: @registry.metadata.deep_merge('packagist_malware' => {'packages' => {'vendor/library' => '*'}}))
    ENV['FROM_ID'] = ENV['TO_ID'] = selected.id.to_s
    upstream(selected.name, canonical_name: other.name)

    output = apply

    assert output.last['complete']
    assert_equal 'Vendor/Library', selected.reload.name
    assert_equal [selected_flag], selected.metadata['malware']
    assert_equal [selected_flag], selected_version.reload.metadata['malware']
    assert_equal 'malware', selected_version.status
    assert_equal @time.to_i, selected.metadata.dig('packagist_snapshot', 'last_modified')
    assert_equal other_before, other.reload.attributes
    assert_equal other_version_before, other_version.reload.attributes
  end

  test 'case-distinct cleanup rejects a snapshot older than the selected record' do
    selected = create_package('Vendor/Library')
    other = create_package('vendor/library')
    selected.update!(metadata: {'packagist_snapshot' => {'last_modified' => (@time + 1.day).to_i, 'sha256' => 'selected'}})
    selected_before = selected.attributes
    other_before = other.attributes
    ENV['FROM_ID'] = ENV['TO_ID'] = selected.id.to_s
    upstream(selected.name, canonical_name: other.name)

    assert_raises(SystemExit) { apply(failure: true) }

    assert_match(/snapshot/, checkpoint['failures'][selected.id.to_s]['error'])
    assert_equal selected_before, selected.reload.attributes
    assert_equal other_before, other.reload.attributes
  end

  test 'case-distinct cleanup still rejects concurrent updates to the selected record' do
    selected = create_package('Vendor/Library')
    other = create_package('vendor/library')
    other_before = other.attributes
    ENV['FROM_ID'] = ENV['TO_ID'] = selected.id.to_s
    upstream(selected.name, canonical_name: other.name)
    stub_request(:get, 'https://repo.packagist.org/p2/vendor/library.json').to_return do
      selected.update!(description: 'concurrent update', updated_at: @time + 1.second)
      {body: {packages: {'vendor/library' => [release('1.0.0')]}}.to_json, headers: {'Last-Modified' => @time.httpdate}}
    end

    assert_raises(SystemExit) { apply(failure: true) }

    assert_equal 'concurrent update', selected.reload.description
    assert_empty selected.versions
    assert_match(/changed during sync/, checkpoint['failures'][selected.id.to_s]['error'])
    assert_equal other_before, other.reload.attributes
  end

  test 'bounded runs resume by name and exclude packages created after the initial upper bound' do
    first = create_package('a/first', status: 'removed')
    second = create_package('b/second', status: 'abandoned')
    upstream(first.name)
    upstream(second.name)
    ENV['LIMIT'] = '1'

    first_output = apply
    late = create_package('c/late')
    second_output = apply
    third_output = apply

    assert_equal first.name, first_output.last['after_name']
    assert_not first_output.last['complete']
    assert_equal second.id, second_output.last['max_id']
    assert_equal 2, second_output.last['processed']
    assert second_output.last['complete']
    assert_equal 0, third_output.last['attempted']
    assert_nil late.reload.last_synced_at
    assert_requested(:get, "https://repo.packagist.org/p2/#{first.name}.json", times: 1)
    assert_requested(:get, "https://repo.packagist.org/p2/#{second.name}.json", times: 1)
  end

  test 'failed packages are reported and retried before advancing further' do
    first = create_package('a/first')
    second = create_package('b/second')
    stub_request(:get, "https://packagist.org/packages/#{first.name}.json").to_return(status: 503)
    upstream(second.name)

    assert_raises(SystemExit) { apply(failure: true) }

    state = checkpoint
    assert_equal second.name, state['after_name']
    assert_equal [first.id.to_s], state['failures'].keys
    assert_equal 1, state['failures'][first.id.to_s]['attempts']
    assert_nil first.reload.last_synced_at
    assert second.reload.last_synced_at
    upstream(first.name)

    output = apply

    assert_empty checkpoint['failures']
    assert_equal 2, output.last['processed']
    assert output.last['complete']
    assert_requested(:get, "https://repo.packagist.org/p2/#{second.name}.json", times: 1)
  end

  test 'a failure after sync rolls back package changes but records the retry' do
    package = create_package('vendor/library')
    package.update!(repository_url: 'https://github.com/old/library', repo_metadata: {'full_name' => 'old/library'},
      repo_metadata_updated_at: @time, issue_metadata: {'past_year_issues_count' => 10})
    version = package.versions.create!(number: '1.0.0', registry: @registry, metadata: {'custom' => 'keep'})
    before = package.reload.attributes
    before_version = version.attributes
    upstream(package.name, [release('2.0.0')])
    Cleanup::Packagist.any_instance.stubs(:remove_platform_dependencies).raises('cleanup failed')

    assert_raises(SystemExit) { apply(failure: true) }

    assert_equal before, package.reload.attributes
    assert_equal before_version, version.reload.attributes
    assert_equal ['1.0.0'], package.versions.pluck(:number)
    assert_equal 0, checkpoint['processed']
    assert_match(/cleanup failed/, checkpoint['failures'][package.id.to_s]['error'])
  end

  test 'missing packages retain versions clear latest fields and receive summary malware flags' do
    package = create_package('vendor/gone')
    version = package.versions.create!(number: '1.0.0', registry: @registry, latest: true)
    package.update!(latest_release_number: '1.0.0')
    @registry.update!(metadata: @registry.metadata.deep_merge('packagist_malware' => {'packages' => {package.name => '*'}}))
    stub_request(:get, "https://packagist.org/packages/#{package.name}.json").to_return(status: 404)
    stub_request(:get, "https://repo.packagist.org/p2/#{package.name}.json").to_return(status: 404)

    apply

    assert_equal 'removed', package.reload.status
    assert_nil package.latest_release_number
    assert_equal 1, package.versions_count
    assert_equal 'removed', version.reload.status
    assert_equal '*', version.metadata['malware'].first['constraint']
    assert_not version.latest
    assert_requested(:get, "https://repo.packagist.org/p2/#{package.name}.json", times: 1)
  end

  test 'withdrawn malware flags clear on removed packages without restoring releases' do
    package = create_package('vendor/gone', status: 'removed')
    flag = {'constraint' => '*', 'classification' => 'malware', 'source' => 'packagist'}
    package.update!(metadata: {'malware' => [flag]})
    version = package.versions.create!(number: '1.0.0', registry: @registry, status: 'removed', metadata: {'malware' => [flag]})
    stub_request(:get, "https://packagist.org/packages/#{package.name}.json").to_return(status: 404)
    stub_request(:get, "https://repo.packagist.org/p2/#{package.name}.json").to_return(status: 404)

    apply

    assert_empty package.reload.metadata['malware']
    assert_nil version.reload.metadata['malware']
    assert_equal 'removed', version.status
    assert_equal 'removed', package.status
  end

  test 'case insensitive name scope preserves IDs when upstream uses canonical casing' do
    package = create_package('Vendor/Library')
    other = create_package('vendor/other')
    upstream(package.name, canonical_name: 'vendor/library')
    ENV['NAME'] = 'VENDOR/LIBRARY'

    output = apply

    assert_equal package.id, output.find { |row| row['event'] == 'applied' }['id']
    assert_equal 'Vendor/Library', package.reload.name
    assert_equal ['1.0.0'], package.versions.pluck(:number)
    assert_nil other.reload.last_synced_at
  end

  test 'ID scopes are inclusive and checkpoints reject changes of scope' do
    first = create_package('a/first')
    second = create_package('b/second')
    upstream(second.name)
    ENV['FROM_ID'] = second.id.to_s
    ENV['TO_ID'] = second.id.to_s

    output = apply

    assert_equal 1, output.last['processed']
    assert_nil first.reload.last_synced_at
    ENV['FROM_ID'] = first.id.to_s
    assert_raises(ArgumentError) { apply }
    assert_nil first.reload.last_synced_at
  end

  test 'a different run can use a separate validation scope' do
    package = create_package('vendor/library')
    upstream(package.name)
    ENV['NAME'] = package.name
    ENV['RUN'] = 'sample'
    apply
    ENV.delete('NAME')
    ENV['RUN'] = 'all'

    apply

    assert_equal %w[all sample], @registry.reload.metadata['packagist_cleanup'].keys.sort
  end

  test 'resumes a Packagist checkpoint saved before the runner extraction' do
    first = create_package('a/first')
    second = create_package('b/second')
    @registry.update!(metadata: @registry.metadata.merge('packagist_cleanup' => {'all' => {
      'scope' => {'from_id' => 0, 'to_id' => nil, 'name' => nil}, 'max_id' => second.id,
      'after_name' => first.name, 'processed' => 1, 'platform_dependencies_removed' => 3, 'failures' => {}}}))
    upstream(second.name)

    output = apply

    assert_equal 2, output.last['processed']
    assert_equal 3, output.last['platform_dependencies_removed']
    assert output.last['complete']
    assert_not_requested(:get, "https://packagist.org/packages/#{first.name}.json")
  end

  test 'only Composer platform edges are removed and affected dependent counts are repaired' do
    package = create_package('vendor/library')
    target = create_package('vendor/target')
    version = package.versions.create!(number: '1.0.0', registry: @registry)
    version.dependencies.create!(package_name: 'ext-json', requirements: '*', ecosystem: 'packagist', package: target, kind: 'runtime')
    foreign = version.dependencies.create!(package_name: 'ext-json', requirements: '*', ecosystem: 'npm', kind: 'runtime')
    real = version.dependencies.create!(package_name: 'ext-json/package', requirements: '*', ecosystem: 'packagist', kind: 'Development')
    target.update!(dependent_packages_count: 1)
    upstream(package.name)
    ENV['NAME'] = package.name

    apply

    assert_equal [foreign.id, real.id].sort, version.dependencies.pluck(:id).sort
    assert_equal 0, target.reload.dependent_packages_count
  end

  test 'stale snapshots fail without deleting historical dependencies' do
    package = create_package('vendor/library')
    package.update!(metadata: {'packagist_snapshot' => {'last_modified' => (@time + 1.day).to_i, 'sha256' => 'newer'}})
    version = package.versions.create!(number: '1.0.0', registry: @registry)
    dependency = version.dependencies.create!(package_name: 'ext-json', requirements: '*', ecosystem: 'packagist')
    upstream(package.name)

    assert_raises(SystemExit) { apply(failure: true) }

    assert Dependency.exists?(dependency.id)
    assert_nil package.reload.last_synced_at
    assert_equal [package.id.to_s], checkpoint['failures'].keys
  end

  test 'invalid options fail before any upstream request' do
    %w[0 -1 bad].each do |limit|
      ENV['LIMIT'] = limit
      assert_raises(ArgumentError) { invoke }
    end
    ENV.delete('LIMIT')
    ENV['DRY_RUN'] = 'no'
    assert_raises(ArgumentError) { invoke }
    ENV['DRY_RUN'] = 'true'
    ENV['NAME'] = ''
    assert_raises(ArgumentError) { invoke }
    assert_not_requested(:get, %r{https://(repo\.)?packagist\.org/})
  end

  test 'apply requires a malware summary while dry run remains available' do
    create_package('vendor/library')
    @registry.update!(metadata: {})
    assert_equal 'preview', invoke[1]['event']
    assert_raises(RuntimeError) { apply }
    assert_not_requested(:get, %r{https://(repo\.)?packagist\.org/})
  end

  test 'another process cannot run cleanup for the same registry' do
    connection = PG.connect(Registry.connection.raw_connection.conninfo_hash.compact)
    connection.exec_params('SELECT pg_advisory_lock(hashtextextended($1, 0))', ["registry_cleanup:#{@registry.id}"])
    error = assert_raises(RuntimeError) { invoke }
    assert_match(/Another cleanup/, error.message)
  ensure
    connection&.close
  end

  test 'failure storage is bounded and unattempted packages stay beyond the checkpoint' do
    packages = 101.times.map { |index| create_package("vendor/package-#{index.to_s.rjust(3, '0')}") }
    stub_request(:get, %r{https://packagist.org/packages/vendor/package-\d+\.json}).to_return(status: 503)
    ENV['LIMIT'] = '1000'

    assert_raises(SystemExit) { apply(failure: true) }

    assert_equal 100, checkpoint['failures'].size
    assert_equal packages[99].name, checkpoint['after_name']
    assert_not_requested(:get, "https://packagist.org/packages/#{packages.last.name}.json")
  end

  test 'a concurrent summary update preserves package state and the new registry metadata' do
    package = create_package('vendor/library')
    upstream(package.name)
    stub_request(:get, "https://repo.packagist.org/p2/#{package.name}.json").to_return do
      @registry.update!(metadata: @registry.metadata.deep_merge('packagist_malware' => {'packages' => {package.name => '*'}}))
      {body: {packages: {package.name => [release('1.0.0')]}}.to_json, headers: {'Last-Modified' => @time.httpdate}}
    end

    assert_raises(SystemExit) { apply(failure: true) }

    assert_empty package.versions
    assert_nil package.reload.last_synced_at
    assert_equal '*', @registry.reload.metadata.dig('packagist_malware', 'packages', package.name)
    assert_equal [package.id.to_s], checkpoint['failures'].keys
  end

  test 'the registry rate limit sets a minimum pause between packages' do
    package = create_package('vendor/library')
    @registry.update!(rate_limit: 2)
    upstream(package.name)
    Cleanup::Packagist.any_instance.expects(:sleep).with(0.5)

    apply
  end

  test 'an output failure after commit leaves a successful checkpoint and releases the lock' do
    package = create_package('vendor/library')
    upstream(package.name)
    output = mock
    output.expects(:puts).with { |line| JSON.parse(line)['event'] == 'start' }
    output.expects(:puts).with { |line| JSON.parse(line)['event'] == 'applied' }.raises(IOError, 'output closed')

    assert_raises(IOError) { Cleanup::Packagist.new(@registry, dry_run: false, pause: 0, output: output).run }

    assert_equal 1, checkpoint['processed']
    assert_empty checkpoint['failures']
    assert_equal 0, apply.last['attempted']
  end

  test 'time budget stops between packages and keeps the next package resumable' do
    first = create_package('a/first')
    second = create_package('b/second')
    upstream(first.name)
    upstream(second.name)
    Process.stubs(:clock_gettime).returns(0.0)
    stub_request(:get, "https://repo.packagist.org/p2/#{first.name}.json").to_return do
      Process.stubs(:clock_gettime).returns(2.0)
      {body: {packages: {first.name => [release('1.0.0')]}}.to_json, headers: {'Last-Modified' => @time.httpdate}}
    end
    ENV['MAX_SECONDS'] = '1'

    output = apply

    assert_equal 1, output.last['attempted']
    assert_equal first.name, checkpoint['after_name']
    assert_not output.last['complete']
    assert_nil second.reload.last_synced_at
  end

  test 'the pause cannot exceed the remaining time budget' do
    package = create_package('vendor/library')
    upstream(package.name)
    ENV['MAX_SECONDS'] = '1'
    ENV['PAUSE'] = '60'
    Process.stubs(:clock_gettime).returns(0.0)
    Cleanup::Packagist.any_instance.expects(:sleep).with do |duration|
      Process.stubs(:clock_gettime).returns(1.0)
      duration == 1.0
    end

    assert_equal 1, apply.last['attempted']
  end

  def invoke(failure: false)
    exit_error = nil
    output, errors = capture_io do
      task = Rake::Task['packages:cleanup_packagist']
      task.reenable
      begin
        task.invoke
      rescue SystemExit => error
        exit_error = error
      end
    end
    raise exit_error if exit_error && failure
    raise "#{errors}\n#{output}" if exit_error
    output.lines.filter_map { |line| JSON.parse(line) if line.start_with?('{') }
  end

  def apply(failure: false)
    ENV['DRY_RUN'] = 'false'
    invoke(failure: failure)
  end

  def checkpoint
    @registry.reload.metadata.fetch('packagist_cleanup').fetch(ENV.fetch('RUN', 'all'))
  end

  def create_package(name, status: 'active')
    @registry.packages.create!(name: name, ecosystem: 'packagist', status: status)
  end

  def upstream(name, versions = [release('1.0.0')], malware: [], canonical_name: name)
    versions = versions.map { |version| version.merge('name' => canonical_name) }
    full = {'package' => {'name' => canonical_name, 'description' => 'Example',
      'versions' => versions.index_by { |version| version['version'] }, 'maintainers' => [], 'downloads' => {'total' => 10}}}
    stub_request(:get, "https://packagist.org/packages/#{name}.json").to_return(body: full.to_json)
    tagged = {'packages' => {canonical_name => versions}, 'filter' => {'malware' => malware}}
    stub_request(:get, "https://repo.packagist.org/p2/#{canonical_name}.json")
      .to_return(body: tagged.to_json, headers: {'Last-Modified' => @time.httpdate})
  end

  def release(number)
    {'version' => number, 'time' => '2026-11-01T00:00:00Z', 'published-time' => '2026-11-02T00:00:00Z',
      'license' => ['MIT'], 'require' => {'php' => '^8', 'ext-json' => '*', 'vendor/dependency' => '^2'},
      'require-dev' => {'ext-xdebug' => '*'}, 'provide' => {'psr/log-implementation' => '*'},
      'replace' => {'vendor/old' => 'self.version'}, 'conflict' => {'vendor/conflict' => '<2'},
      'source' => {'type' => 'git', 'url' => 'https://github.com/example/library', 'reference' => 'abc'},
      'dist' => {'type' => 'zip', 'url' => "https://example.com/#{number}.zip", 'reference' => 'abc', 'shasum' => 'a' * 40}}
  end
end
