require 'test_helper'

class PackagistReconciliationTest < ActiveSupport::TestCase
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    @time = Time.current.change(usec: 0)
    @registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @package = @registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', status: 'active')
    stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(body: file_fixture('packagist/log.json.1'))
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(body: {packages: {'psr/log' => [{version: 'dev-master'}]}}.to_json)
    tagged_body(file_fixture('packagist/log.p2.json').read)
  end

  %w[changes versions].each do |path|
    test "#{path} refresh updates existing metadata without a new release" do
      SyncPackageWorker.new.perform(@registry.id, 'psr/log', true)
      version = @package.versions.find_by!(number: '3.0.2')
      original = version.metadata.deep_dup
      publication = version.published_at
      dependency = version.dependencies.create!(package_name: 'vendor/library', ecosystem: 'packagist', requirements: '^1', kind: 'runtime')
      ids = @package.versions.order(:id).pluck(:id)
      version.update!(published_at: 20.years.ago, metadata: {'php_version' => '^5.6', 'suggest' => {'obsolete' => '*'}, 'custom' => 'keep'})

      refresh(path)

      assert_equal original.merge('custom' => 'keep'), version.reload.metadata
      assert_equal publication, version.published_at
      assert_equal ids, @package.versions.order(:id).pluck(:id)
      assert Dependency.exists?(dependency.id)
      assert_equal '3.0.2', @package.reload.latest_release_number
    end

    test "#{path} refresh removes and restores releases without replacing their records" do
      tagged([release('1.0.0'), release('2.0.0')])
      refresh(path)
      version = @package.versions.find_by!(number: '2.0.0')
      dependency = version.dependencies.create!(package_name: 'vendor/library', ecosystem: 'packagist', requirements: '^1', kind: 'runtime')
      ids = @package.versions.order(:id).pluck(:id)
      tagged([release('1.0.0')])

      refresh(path)

      assert_equal 'removed', version.reload.status
      assert_equal '1.0.0', @package.reload.latest_release_number
      assert_equal ids, @package.versions.order(:id).pluck(:id)
      assert Dependency.exists?(dependency.id)
      tagged([release('1.0.0'), release('2.0.0', 'require' => {'php' => '>=8.2'})])
      refresh(path)
      assert_nil version.reload.status
      assert_equal '>=8.2', version.metadata['php_version']
      assert_equal '2.0.0', @package.reload.latest_release_number
      assert_equal ids, @package.versions.order(:id).pluck(:id)
      assert Dependency.exists?(dependency.id)
    end

    test "#{path} refresh preserves leading-v aliases and distinct releases with the same checksum" do
      version = @package.versions.create!(number: '4.4.3', integrity: 'sha1-same', status: 'removed', metadata: {'custom' => true})
      dependency = version.dependencies.create!(package_name: 'vendor/library', ecosystem: 'packagist', requirements: '^1', kind: 'runtime')
      tagged([release('v4.4.3', 'dist' => {'url' => 'https://example.test/shared.zip', 'shasum' => 'same'}),
        release('v4.4.4', 'dist' => {'url' => 'https://example.test/shared.zip', 'shasum' => 'same'})])

      refresh(path)

      assert_equal '4.4.3', version.reload.number
      assert_nil version.status
      assert_equal '>=8.0', version.metadata['php_version']
      assert_equal true, version.metadata['custom']
      assert_equal ['4.4.3', 'v4.4.4'], @package.versions.order(:number).pluck(:number)
      assert_equal 'v4.4.4', @package.reload.latest_release_number
      assert_equal @registry.id, @package.versions.find_by!(number: 'v4.4.4').registry_id
      assert_equal version.id, dependency.reload.version_id
    end

    test "#{path} refresh preserves both existing alias records and their dependencies" do
      bare = @package.versions.create!(number: '1.0.0', status: 'removed')
      prefixed = @package.versions.create!(number: 'V1.0.0', status: 'yanked')
      dependencies = [bare, prefixed].map { |version| version.dependencies.create!(package_name: 'vendor/library', ecosystem: 'packagist', requirements: '*', kind: 'runtime') }
      tagged([release('v1.0.0')])

      refresh(path)

      assert_equal ['1.0.0', 'V1.0.0'], @package.versions.order(:number).pluck(:number)
      assert_nil bare.reload.status
      assert_equal 'yanked', prefixed.reload.status
      [bare, prefixed].each { |version| assert_equal '>=8.0', version.metadata['php_version'] }
      dependencies.each { |dependency| assert Dependency.exists?(dependency.id) }
    end

    test "#{path} refresh removes unset fields from existing versions in minified metadata" do
      version = @package.versions.create!(number: '1.0.0', metadata: {'download_url' => 'old', 'php_version' => '^5',
        'platform_requirements' => {'ext-json' => '*'}, 'autoload' => {'old' => true}, 'extra' => {'old' => true},
        'suggest' => {'old' => '*'}, 'custom' => 'keep'})
      latest = release('2.0.0', 'autoload' => {'psr-4' => {'Example\\' => 'src/'}}, 'extra' => {'new' => true}, 'suggest' => {'vendor/optional' => '*'})
      older = {'version' => '1.0.0', 'require' => '__unset', 'dist' => '__unset', 'autoload' => '__unset', 'extra' => '__unset', 'suggest' => '__unset'}
      tagged_body({minified: 'composer/2.0', packages: {'psr/log' => [latest, older]}}.to_json)

      refresh(path)

      assert_equal({'custom' => 'keep'}, version.reload.metadata)
    end

    test "#{path} refresh reconciles a complete empty response without release enrichment" do
      version = @package.versions.create!(number: '1.0.0')
      tagged([])
      enrichment = JSON.parse(file_fixture('packagist/log.json.1').read)
      enrichment['package']['versions'] = {}
      stub_request(:get, 'https://packagist.org/packages/psr/log.json').to_return(body: enrichment.to_json)

      refresh(path)

      assert_equal 'removed', version.reload.status
      assert_nil @package.reload.latest_release_number
      assert_equal 1, @package.versions.count
    end

    test "#{path} refresh preserves computed integrity for the same archive and clears it for a different one" do
      tagged([release('1.0.0')])
      refresh(path)
      version = @package.versions.find_by!(number: '1.0.0')
      version.update!(integrity: 'sha256-computed')

      refresh(path)
      assert_equal 'sha256-computed', version.reload.integrity
      tagged([release('1.0.0', 'dist' => {'url' => 'https://example.test/changed.zip'})])
      refresh(path)
      assert_nil version.reload.integrity
      tagged([release('1.0.0', 'dist' => {'url' => 'https://example.test/changed.zip', 'shasum' => 'upstream'})])
      refresh(path)
      assert_equal 'sha1-upstream', version.reload.integrity
    end

    test "#{path} refresh preserves malware classifications on removed releases" do
      flag = {'constraint' => '2.0.0', 'source' => 'aikido', 'id' => 'PKFE-example', 'reason' => 'malware'}
      version = @package.versions.create!(number: '2.0.0', status: 'malware', metadata: {'malware' => [flag]})
      tagged([release('1.0.0')], flags: [flag])
      refresh(path)
      assert_equal 'removed', version.reload.status
      assert_equal 'PKFE-example', version.metadata['malware'].first['id']
      tagged([release('1.0.0'), release('2.0.0')], flags: [flag])
      refresh(path)
      assert_equal 'malware', version.reload.status
      assert_equal '1.0.0', @package.reload.latest_release_number
    end

    test "#{path} refresh leaves versions untouched after failed or malformed snapshots" do
      version = @package.versions.create!(number: '1.0.0', metadata: {'custom' => true})
      original = version.attributes
      invalid = [
        {packages: {}},
        {packages: {'psr/log' => {}}},
        {packages: {'psr/log' => [release('1.0.0'), release('v1.0.0')]}},
        {packages: {'psr/log' => [release('1.0.0'), {'version' => 3}]}},
        {minified: 'unsupported', packages: {'psr/log' => []}}
      ]
      invalid.each do |body|
        tagged_body(body.to_json)
        assert_raises(StandardError) { refresh(path) }
        assert_equal original, version.reload.attributes
        assert_nil Rails.cache.read(['packagist', 'tagged_versions', 'psr/log'])
      end
      stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json').to_return(status: 503)
      assert_raises(RuntimeError) { refresh(path) }
      assert_equal original, version.reload.attributes
    end

    test "#{path} refresh reconciles a complete cached snapshot after HTTP 304" do
      tagged([release('1.0.0')])
      refresh(path)
      version = @package.versions.find_by!(number: '1.0.0')
      version.update!(metadata: {})
      absent = @package.versions.create!(number: '9.0.0')
      stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
        .with(headers: {'If-Modified-Since' => @time.httpdate}).to_return(status: 304)

      refresh(path)

      assert_equal '>=8.0', version.reload.metadata['php_version']
      assert_equal 'removed', absent.reload.status
      assert_equal '1.0.0', @package.reload.latest_release_number
    end
  end

  %w[sync versions].each do |path|
    test "#{path} worker preserves release timestamps, identities and per-version licenses" do
      @package.update!(licenses: 'MIT')
      source = {'type' => 'git', 'url' => 'https://github.com/php-fig/log.git', 'reference' => 'a' * 40}
      dist = {'type' => 'zip', 'url' => 'https://example.test/2.0.0.zip', 'reference' => 'b' * 40, 'shasum' => 'c' * 40}
      older_source = source.merge('reference' => 'd' * 40)
      older_dist = dist.merge('url' => 'https://example.test/1.0.0.zip', 'reference' => 'e' * 40, 'shasum' => '')
      tagged([
        release('2.0.0', 'published-time' => '2024-09-11T13:21:14+00:00', 'license' => ['Apache-2.0'], 'source' => source, 'dist' => dist),
        release('1.0.0', 'time' => '2021-07-14T16:46:02+00:00', 'published-time' => '2021-07-14T16:46:29+00:00',
          'license' => ['MIT', 'BSD-3-Clause'], 'source' => older_source, 'dist' => older_dist)
      ])

      refresh(path)

      latest = @package.versions.find_by!(number: '2.0.0')
      older = @package.versions.find_by!(number: '1.0.0')
      assert_equal Time.iso8601('2024-09-11T13:17:53+00:00'), latest.published_at
      assert_equal '2024-09-11T13:21:14+00:00', latest.metadata['published-time']
      assert_equal Time.iso8601('2021-07-14T16:46:02+00:00'), older.published_at
      assert_equal '2021-07-14T16:46:29+00:00', older.metadata['published-time']
      assert_equal 'Apache-2.0', latest.licenses
      assert_equal 'MIT,BSD-3-Clause', older.licenses
      assert_equal 'MIT', @package.reload.licenses
      assert_equal source, latest.metadata['source']
      assert_equal dist.except('shasum'), latest.metadata['dist']
      assert_equal dist['url'], latest.metadata['download_url']
      assert_equal "sha1-#{'c' * 40}", latest.integrity
      assert_equal older_source, older.metadata['source']
      assert_equal older_dist.except('shasum'), older.metadata['dist']
      assert_nil older.integrity
    end

    test "#{path} worker refreshes release metadata and clears removed optional fields without replacing records" do
      version = @package.versions.create!(number: '1.0.0', published_at: 20.years.ago, licenses: 'GPL-3.0-only', metadata: {'custom' => {'keep' => true}})
      ids = @package.versions.order(:id).pluck(:id)
      source = {'type' => 'git', 'url' => 'https://github.com/php-fig/log.git', 'reference' => 'a' * 40}
      dist = {'type' => 'zip', 'url' => 'https://example.test/1.0.0.zip', 'reference' => 'b' * 40, 'shasum' => 'c' * 40}
      tagged([release('1.0.0', 'published-time' => '2024-09-11T13:21:14+00:00', 'license' => ['MIT', 'BSD-3-Clause'], 'source' => source, 'dist' => dist)])

      refresh(path)

      assert_equal Time.iso8601('2024-09-11T13:17:53+00:00'), version.reload.published_at
      assert_equal '2024-09-11T13:21:14+00:00', version.metadata['published-time']
      assert_equal 'MIT,BSD-3-Clause', version.licenses
      assert_equal source, version.metadata['source']
      assert_equal dist.except('shasum'), version.metadata['dist']
      assert_equal({'keep' => true}, version.metadata['custom'])
      assert_equal ids, @package.versions.order(:id).pluck(:id)

      tagged([release('1.0.0', 'source' => source.slice('url'), 'dist' => dist.slice('url'))])
      refresh(path)

      assert_not version.reload.metadata.key?('published-time')
      assert_equal '', version.licenses
      assert_equal source.slice('url'), version.metadata['source']
      assert_equal dist.slice('url'), version.metadata['dist']
      assert_equal dist['url'], version.metadata['download_url']
      assert_equal "sha1-#{'c' * 40}", version.integrity
      assert_equal({'keep' => true}, version.metadata['custom'])
      assert_equal ids, @package.versions.order(:id).pluck(:id)

      tagged([release('1.0.0').except('dist')])
      refresh(path)

      version.reload
      %w[published-time source dist download_url].each { |key| assert_not version.metadata.key?(key) }
      assert_equal '', version.licenses
      assert_nil version.integrity
      assert_equal({'keep' => true}, version.metadata['custom'])
      assert_equal ids, @package.versions.order(:id).pluck(:id)
    end

    test "#{path} worker expands inherited release metadata and unsets it in minified responses" do
      source = {'type' => 'git', 'url' => 'https://github.com/php-fig/log.git', 'reference' => 'a' * 40}
      dist = {'type' => 'zip', 'url' => 'https://example.test/shared.zip', 'reference' => 'b' * 40}
      latest = release('3.0.0', 'published-time' => '2024-09-11T13:21:14+00:00', 'license' => ['MIT'], 'source' => source, 'dist' => dist)
      inherited = {'version' => '2.0.0', 'license' => ['BSD-3-Clause', 'Apache-2.0']}
      unset = {'version' => '1.0.0', 'published-time' => '__unset', 'source' => '__unset', 'dist' => '__unset', 'license' => '__unset'}
      tagged_body({minified: 'composer/2.0', packages: {'psr/log' => [latest, inherited, unset]}}.to_json)

      refresh(path)

      assert_equal 'MIT', @package.versions.find_by!(number: '3.0.0').licenses
      version = @package.versions.find_by!(number: '2.0.0')
      assert_equal Time.iso8601('2024-09-11T13:17:53+00:00'), version.published_at
      assert_equal '2024-09-11T13:21:14+00:00', version.metadata['published-time']
      assert_equal 'BSD-3-Clause,Apache-2.0', version.licenses
      assert_equal source, version.metadata['source']
      assert_equal dist, version.metadata['dist']
      assert_equal dist['url'], version.metadata['download_url']
      assert_nil version.integrity
      older = @package.versions.find_by!(number: '1.0.0')
      assert_equal '', older.licenses
      %w[published-time source dist download_url].each { |key| assert_not older.metadata.key?(key) }
      assert_equal Time.iso8601('2024-09-11T13:17:53+00:00'), older.published_at
      assert_nil older.integrity
    end
  end

  test 'dependency lookup uses the upstream release when the stored label has no v prefix' do
    version = @package.versions.create!(number: '1.0.0')
    tagged([release('v1.0.0', 'require' => {'php' => '>=8.0', 'psr/container' => '^2'}), release('2.0.0')])

    refresh('changes')

    assert_equal ['psr/container'], version.dependencies.pluck(:package_name)
    assert_equal ['1.0.0', '2.0.0'], @package.versions.order(:number).pluck(:number)
  end

  def refresh(path)
    if path == 'sync'
      SyncPackageWorker.new.perform(@registry.id, 'psr/log', true)
    elsif path == 'changes'
      SyncPackagistChangeWorker.new.perform(@registry.id, {'type' => 'update', 'package' => 'psr/log', 'time' => @time.to_i})
    else
      UpdateVersionsWorker.new.perform(@package.id)
    end
  end

  def release(number, attributes = {})
    {'name' => 'psr/log', 'version' => number, 'time' => '2024-09-11T13:17:53+00:00',
      'dist' => {'url' => "https://example.test/#{number}.zip"}, 'require' => {'php' => '>=8.0'}}.merge(attributes)
  end

  def tagged(versions, flags: [])
    tagged_body({packages: {'psr/log' => versions}, filter: {malware: flags}}.to_json)
  end

  def tagged_body(body)
    @time += 1.second
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .to_return(body: body, headers: {'Last-Modified' => @time.httpdate})
  end
end
