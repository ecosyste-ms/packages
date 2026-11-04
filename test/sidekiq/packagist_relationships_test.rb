require 'test_helper'

class PackagistRelationshipsTest < ActiveSupport::TestCase
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
    @platform = {'php' => '^8.1', 'php-64bit' => '*', 'php-ipv6' => '*', 'php-zts' => '*', 'php-debug' => '*',
      'hhvm' => '^4', 'ext-json' => '*', 'lib-curl' => '>=7', 'composer' => '^2',
      'composer-plugin-api' => '^2', 'composer-runtime-api' => '^2'}
    @development_platform = {'PHP' => '^8.2', 'ext-mbstring' => '*', 'EXT-XDEBUG' => '^3', 'lib-libxml' => '*',
      'composer-runtime-api' => '^2.2'}
    @relationships = {'provide' => {'psr/log-implementation' => '1.0 || 2.0', 'ext-json' => '*'},
      'replace' => {'vendor/old-library' => 'self.version'},
      'conflict' => {'vendor/incompatible' => '<2', 'php' => '<8.1'}}
  end

  %w[sync versions].each do |path|
    test "#{path} collects platform scopes and preserves distinct relationships" do
      tagged([release('1.0.0')])

      perform(path)

      metadata = @package.versions.find_by!(number: '1.0.0').metadata
      assert_equal @platform, metadata['platform_requirements']
      assert_equal @development_platform, metadata['platform_requirements_dev']
      assert_equal '^8.1', metadata['php_version']
      assert_equal @relationships, metadata.slice(*@relationships.keys)
    end

    test "#{path} refresh replaces collected relationships and clears removed fields" do
      tagged([release('1.0.0')])
      perform('sync')
      version = @package.versions.find_by!(number: '1.0.0')
      original_id = version.id
      version.update!(metadata: version.metadata.merge('custom' => 'keep'))
      dependencies = version.dependencies.order(:id).pluck(:id, :package_name, :requirements, :kind)
      tagged([release('1.0.0').merge('require' => {'php' => '^8.3'}, 'require-dev' => {},
        'provide' => {'psr/log-implementation' => '3.0'}, 'replace' => {}, 'conflict' => {})])

      perform(path)

      version.reload
      assert_equal original_id, version.id
      assert_equal 'keep', version.metadata['custom']
      assert_equal({'php' => '^8.3'}, version.metadata['platform_requirements'])
      assert_equal({'psr/log-implementation' => '3.0'}, version.metadata['provide'])
      assert_nil version.metadata['platform_requirements_dev']
      assert_nil version.metadata['replace']
      assert_nil version.metadata['conflict']
      assert_equal dependencies, version.dependencies.order(:id).pluck(:id, :package_name, :requirements, :kind)

      tagged([{'name' => 'psr/log', 'version' => '1.0.0'}])
      perform(path)
      metadata = version.reload.metadata
      assert_equal 'keep', metadata['custom']
      assert_empty metadata.slice('platform_requirements', 'platform_requirements_dev', 'php_version', 'provide', 'replace', 'conflict')
    end

    test "#{path} expands inherited and unset relationship metadata per release" do
      tagged([release('2.0.0'), {'version' => '1.0.0'}, {'version' => '0.9.0',
        'require' => '__unset', 'require-dev' => '__unset', 'provide' => '__unset',
        'replace' => '__unset', 'conflict' => '__unset'}], minified: true)

      perform(path)

      inherited = @package.versions.find_by!(number: '1.0.0').metadata
      assert_equal @platform, inherited['platform_requirements']
      assert_equal @development_platform, inherited['platform_requirements_dev']
      assert_equal @relationships, inherited.slice(*@relationships.keys)
      cleared = @package.versions.find_by!(number: '0.9.0').metadata
      assert_empty cleared.slice('platform_requirements', 'platform_requirements_dev', 'php_version', 'provide', 'replace', 'conflict')
    end
  end

  test 'normal sync creates only package dependency edges and keeps their scopes' do
    tagged([release('1.0.0')])

    perform('sync')

    dependencies = @package.versions.find_by!(number: '1.0.0').dependencies
    assert_equal [['composer/composer', '^2', 'Development'], ['ext-json/package', '*', 'runtime'],
      ['php-http/client-implementation', '^1', 'runtime'], ['vendor/library', '^2', 'runtime'],
      ['vendor/tests', '^3', 'Development']], dependencies.order(:package_name).pluck(:package_name, :requirements, :kind)
    assert_equal ['packagist'], dependencies.distinct.pluck(:ecosystem)
  end

  test 'normal sync excludes platform-only requirements from dependency rows' do
    tagged([release('1.0.0').merge('require' => @platform, 'require-dev' => @development_platform)])

    perform('sync')

    version = @package.versions.find_by!(number: '1.0.0')
    assert_empty version.dependencies
    assert_equal @platform, version.metadata['platform_requirements']
    assert_equal @development_platform, version.metadata['platform_requirements_dev']
  end

  def perform(path)
    if path == 'sync'
      SyncPackageWorker.new.perform(@registry.id, 'psr/log', true)
    else
      UpdateVersionsWorker.new.perform(@package.id)
    end
  end

  def tagged(versions, minified: false)
    @time += 1.second
    body = {'packages' => {'psr/log' => versions}}
    body['minified'] = 'composer/2.0' if minified
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log.json')
      .to_return(body: body.to_json, headers: {'Last-Modified' => @time.httpdate})
  end

  def release(number)
    {'name' => 'psr/log', 'version' => number, 'time' => '2026-11-01T00:00:00Z',
      'require' => @platform.merge('vendor/library' => '^2', 'php-http/client-implementation' => '^1', 'ext-json/package' => '*'),
      'require-dev' => @development_platform.merge('vendor/tests' => '^3', 'composer/composer' => '^2')}.merge(@relationships)
  end
end
