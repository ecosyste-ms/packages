require "test_helper"

class DubTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'code.dlang.org', url: 'https://code.dlang.org', ecosystem: 'dub')
    @ecosystem = Ecosystem::Dub.new(@registry)
    @package = Package.new(ecosystem: 'dub', name: 'sily-terminal', metadata: { 'documentation_url' => 'https://example.com/docs' })
    @version = @package.versions.build(number: '4.0.0')
  end

  def stub_info(name)
    stub_request(:get, "https://code.dlang.org/api/packages/#{name}/info")
      .to_return(status: 200, body: file_fixture("dub/#{name}.json"))
  end

  def package_metadata(name)
    stub_info(name)
    @ecosystem.package_metadata(name)
  end

  test 'registry_url' do
    assert_equal 'https://code.dlang.org/packages/sily-terminal', @ecosystem.registry_url(@package)
    assert_equal 'https://code.dlang.org/packages/sily-terminal/4.0.0', @ecosystem.registry_url(@package, @version)
  end

  test 'download_url' do
    assert_equal 'https://code.dlang.org/packages/sily-terminal/4.0.0.zip', @ecosystem.download_url(@package, @version)
    assert_nil @ecosystem.download_url(@package)
  end

  test 'documentation_url' do
    assert_equal 'https://example.com/docs', @ecosystem.documentation_url(@package)
  end

  test 'install_command' do
    assert_equal 'dub add sily-terminal', @ecosystem.install_command(@package)
    assert_equal 'dub add sily-terminal@4.0.0', @ecosystem.install_command(@package, @version)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:dub/sily-terminal@4.0.0', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, 'https://code.dlang.org/packages/index.json')
      .to_return(status: 200, body: file_fixture('dub/index.json'))

    assert_equal %w[dwt sily-terminal vibe-d], @ecosystem.all_package_names
  end

  test 'all_package_names is empty when the index is unavailable' do
    stub_request(:get, 'https://code.dlang.org/packages/index.json').to_return(status: 503, body: 'unavailable')

    assert_equal [], @ecosystem.all_package_names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, 'https://code.dlang.org/?sort=updated&limit=100')
      .to_return(status: 200, body: file_fixture('dub/recently_updated.html'))

    assert_equal %w[fldtk trial parin], @ecosystem.recently_updated_package_names
  end

  test 'package_metadata uses the latest release rather than a branch' do
    metadata = package_metadata('dwt')

    assert_equal 'dwt', metadata[:name]
    assert_equal 'A library for creating cross-platform GUI applications.', metadata[:description]
    assert_equal 'https://github.com/d-widget-toolkit/dwt', metadata[:homepage]
    assert_equal 'EPL-1.0', metadata[:licenses]
    assert_equal 'https://github.com/d-widget-toolkit/dwt', metadata[:repository_url]
    assert_equal ['library.gui'], metadata[:keywords_array]
    assert_equal({ date_added: '2018-02-06T22:42:54' }, metadata[:metadata])
  end

  test 'package_metadata returns false for a missing package' do
    stub_request(:get, 'https://code.dlang.org/api/packages/missing/info').to_return(status: 404, body: '{"statusMessage":"Package not found"}')

    refute @ecosystem.package_metadata('missing')
  end

  test 'package_metadata raises when the registry errors' do
    stub_request(:get, 'https://code.dlang.org/api/packages/dwt/info').to_return(status: 500)

    assert_raises(RuntimeError) { @ecosystem.package_metadata('dwt') }
  end

  test 'check_status' do
    stub_request(:head, 'https://code.dlang.org/packages/sily-terminal').to_return(status: 200)
    stub_request(:head, 'https://code.dlang.org/packages/missing').to_return(status: 404)

    assert_nil @ecosystem.check_status(@package)
    assert_equal 'removed', @ecosystem.check_status(Package.new(ecosystem: 'dub', name: 'missing'))
  end

  test 'repository_url maps each hosting kind' do
    assert_equal 'https://gitlab.com/szabobogdan3/trial', @ecosystem.repository_url('kind' => 'gitlab', 'owner' => 'szabobogdan3', 'project' => 'trial')
    assert_equal 'https://bitbucket.org/denis-sh/unstandard', @ecosystem.repository_url('kind' => 'bitbucket', 'owner' => 'denis-sh', 'project' => 'unstandard')
    assert_equal 'https://codeberg.org/ZILtoid1991/pixelperfectengine', @ecosystem.repository_url('kind' => 'forgejo', 'owner' => 'ZILtoid1991', 'project' => 'pixelperfectengine')
    assert_nil @ecosystem.repository_url('kind' => 'gitea', 'owner' => 'someone', 'project' => 'thing')
    assert_nil @ecosystem.repository_url(nil)
  end

  test 'versions_metadata keeps branches, configurations and subpackages' do
    versions = @ecosystem.versions_metadata(package_metadata('dwt'))

    assert_equal ['~master', '1.0.4+swt-3.4.1', '1.0.5+swt-3.4.1'], versions.map { |version| version[:number] }
    assert_equal 1, versions.map(&:keys).uniq.size

    branch = versions.first
    assert_equal true, branch[:metadata][:branch]
    assert_equal '2026-05-02T20:19:26Z', branch[:published_at]

    release = versions.last
    assert_equal 'EPL-1.0', release[:licenses]
    assert_equal 'c4e35860fbe55718050eb9a6d32b8b18a4c9c89b', release[:metadata][:commit_id]
    refute release[:metadata].key?(:branch)
    assert_equal({ name: 'linux-gtk', platforms: ['linux'], dependencies: { 'dwt:base' => '*' } }, release[:metadata][:configurations].first)
    assert_equal [{ name: 'dwt:base' }], release[:metadata][:subpackages]
  end

  test 'versions_metadata names subpackages under their parent' do
    release = @ecosystem.versions_metadata(package_metadata('sily-terminal')).last

    assert_equal %w[sily-terminal:logger sily-terminal:tui], release[:metadata][:subpackages].map { |subpackage| subpackage[:name] }
    assert_equal({ 'version' => '0.2.0', 'optional' => true }, release[:metadata][:subpackages].last[:dependencies]['speedy-stdio'])
  end

  test 'dependencies_metadata maps requirements and optional dependencies' do
    deps = @ecosystem.dependencies_metadata('sily-terminal', '4.0.0', package_metadata('sily-terminal'))

    assert_equal [
      { package_name: 'sily', requirements: '~>4.0', kind: 'runtime', optional: false, ecosystem: 'dub' },
      { package_name: 'speedy-stdio', requirements: '0.2.0', kind: 'runtime', optional: true, ecosystem: 'dub' },
    ], deps
  end

  test 'dependencies_metadata includes configuration only dependencies once' do
    deps = @ecosystem.dependencies_metadata('dwt', '1.0.5+swt-3.4.1', package_metadata('dwt'))

    assert_equal [{ package_name: 'dwt:base', requirements: '*', kind: 'configuration', optional: false, ecosystem: 'dub' }], deps
  end

  test 'dependencies_metadata prefers the package level declaration over a configuration' do
    pkg = {
      name: 'example',
      versions: [{
        'version' => '1.0.0',
        'dependencies' => { 'vibe-d:core' => { 'path' => '.' }, 'mir' => { 'version' => '~>3.2', 'optional' => true, 'default' => true } },
        'configurations' => [{ 'name' => 'posix', 'platforms' => ['posix'], 'dependencies' => { 'mir' => '~>3.0', 'libevent' => '~>2.0' } }],
      }]
    }

    deps = @ecosystem.dependencies_metadata('example', '1.0.0', pkg)

    assert_equal [['vibe-d:core', '*', 'runtime', false], ['mir', '~>3.2', 'runtime', true], ['libevent', '~>2.0', 'configuration', false]],
                 deps.map { |dep| dep.values_at(:package_name, :requirements, :kind, :optional) }
  end

  test 'dependencies_metadata is empty for an unknown version' do
    assert_equal [], @ecosystem.dependencies_metadata('dwt', '9.9.9', package_metadata('dwt'))
  end

  def sync_dwt(registry_id, info)
    stub_request(:get, 'https://code.dlang.org/api/packages/dwt/info').to_return(status: 200, body: info.to_json)
    stub_request(:head, 'https://code.dlang.org/packages/dwt').to_return(status: 200)
    Registry.find(registry_id).sync_package('dwt', force: true)
  end

  test 'sync_package refreshes an existing branch version when upstream changes' do
    registry = Registry.create!(default: true, name: 'code.dlang.org', url: 'https://code.dlang.org', ecosystem: 'dub')
    info = JSON.parse(file_fixture('dub/dwt.json').read)
    sync_dwt(registry.id, info)

    package = registry.packages.find_by!(name: 'dwt')
    branch = package.versions.find_by!(number: '~master')
    release = package.versions.find_by!(number: '1.0.5+swt-3.4.1')
    branch.update_columns(metadata: branch.metadata.merge('dist_tag' => 'kept'))
    assert_equal ['dwt:base'], branch.dependencies.pluck(:package_name)
    release_state = [release.reload.attributes.slice('metadata', 'published_at', 'licenses'), release.dependencies.pluck(:id)]

    master = info['versions'].find { |version| version['version'] == '~master' }
    master['commitID'] = '0123456789abcdef0123456789abcdef01234567'
    master['date'] = '2026-10-04T12:00:00Z'
    master['license'] = 'BSL-1.0'
    master['dependencies'] = { 'bindbc-gtk' => '~>0.3.0' }
    master.delete('configurations')
    master.delete('subPackages')
    sync_dwt(registry.id, info)

    branch.reload
    assert_equal '0123456789abcdef0123456789abcdef01234567', branch.metadata['commit_id']
    assert_equal Time.utc(2026, 10, 4, 12), branch.read_attribute(:published_at)
    assert_equal 'BSL-1.0', branch.licenses
    assert_equal true, branch.metadata['branch']
    assert_equal 'kept', branch.metadata['dist_tag']
    refute branch.metadata.key?('configurations')
    refute branch.metadata.key?('subpackages')
    assert_equal [['bindbc-gtk', '~>0.3.0', 'runtime', false]], branch.dependencies.pluck(:package_name, :requirements, :kind, :optional)
    assert_equal release_state, [release.reload.attributes.slice('metadata', 'published_at', 'licenses'), release.dependencies.pluck(:id)]
  end

  test 'sync_package leaves an unchanged branch version untouched' do
    registry = Registry.create!(default: true, name: 'code.dlang.org', url: 'https://code.dlang.org', ecosystem: 'dub')
    info = JSON.parse(file_fixture('dub/dwt.json').read)
    sync_dwt(registry.id, info)
    branch = registry.packages.find_by!(name: 'dwt').versions.find_by!(number: '~master')
    state = [branch.updated_at, branch.dependencies.pluck(:id)]

    sync_dwt(registry.id, info)

    assert_equal state, [branch.reload.updated_at, branch.dependencies.pluck(:id)]
  end

  test 'sync_package stores releases, branches and dependencies' do
    registry = Registry.create!(default: true, name: 'code.dlang.org', url: 'https://code.dlang.org', ecosystem: 'dub')
    stub_info('sily-terminal')
    stub_request(:head, 'https://code.dlang.org/packages/sily-terminal').to_return(status: 200)

    registry.sync_package('sily-terminal', force: true)

    package = registry.packages.find_by!(name: 'sily-terminal')
    assert_equal ['1.3.0', '4.0.0', '~master'], package.versions.pluck(:number).sort
    assert_equal true, package.versions.find_by!(number: '~master').metadata['branch']
    assert_equal %w[sily speedy-stdio], package.versions.find_by!(number: '4.0.0').dependencies.order(:package_name).pluck(:package_name)
    assert_equal '4.0.0', package.latest_version.number
  end
end
