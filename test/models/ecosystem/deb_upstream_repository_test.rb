require "test_helper"

class DebUpstreamRepositoryTest < ActiveSupport::TestCase
  UPSTREAM_METADATA = <<~YAML
    Bug-Database: https://github.com/rack/rack/issues
    Repository: https://github.com/rack/rack.git
    Repository-Browse: https://github.com/rack/rack
  YAML

  COPYRIGHT = <<~TEXT
    Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
    Upstream-Name: rack
    Source: https://github.com/rack/rack

    Files: *
    Copyright: 2007-2021 Leah Neukirchen
    Source: https://example.com/not-the-header
  TEXT

  setup do
    @registry = Registry.create!(name: 'debian-13', version: '13', url: 'https://packages.debian.org/trixie', ecosystem: 'debian', metadata: { 'codename' => 'trixie' })
    @ecosystem = @registry.ecosystem_instance
    @package = @registry.packages.create!(name: 'ruby-rack', ecosystem: 'debian', latest_release_number: '3.1.20-0+deb13u2',
                                          homepage: 'https://rack.github.io/', repository_url: 'https://salsa.debian.org/ruby-team/ruby-rack',
                                          metadata: { 'component' => 'main' })
    @sources = 'https://sources.debian.org/data/main/r/ruby-rack/3.1.20-0%2Bdeb13u2'
    @salsa = 'https://salsa.debian.org/ruby-team/ruby-rack/-/raw/HEAD'
  end

  test 'map_package_metadata adds a homepage that is a repository' do
    result = @ecosystem.map_package_metadata(name: 'ruby-rack', homepage: 'https://github.com/rack/rack', repository_url: 'https://salsa.debian.org/ruby-team/ruby-rack',
                                             metadata: { component: 'main' })

    assert_equal 'https://github.com/rack/rack', result[:metadata][:upstream_repository_url]
    assert_equal 'homepage', result[:metadata][:upstream_repository_source]
  end

  test 'map_package_metadata adds no upstream repository for a homepage that is not a repository' do
    result = @ecosystem.map_package_metadata(name: 'ruby-rack', homepage: 'https://rack.github.io/', repository_url: 'https://salsa.debian.org/ruby-team/ruby-rack',
                                             metadata: { component: 'main' })

    assert_equal 'https://salsa.debian.org/ruby-team/ruby-rack', result[:repository_url]
    assert_not result[:metadata].key?(:upstream_repository_url)
  end

  test 'update_upstream_repository reads Repository-Browse from debian/upstream/metadata on sources.debian.org' do
    stub_request(:get, "#{@sources}/debian/upstream/metadata").to_return(status: 200, body: UPSTREAM_METADATA)

    @ecosystem.update_upstream_repository(@package)

    metadata = @package.reload.metadata
    assert_equal 'https://github.com/rack/rack', metadata['upstream_repository_url']
    assert_equal 'debian/upstream/metadata', metadata['upstream_repository_source']
    assert_equal '3.1.20-0+deb13u2', metadata['upstream_repository_checked']
    assert_equal 'main', metadata['component']
    assert_equal 'https://salsa.debian.org/ruby-team/ruby-rack', @package.repository_url
  end

  test 'update_upstream_repository falls back to salsa then to the debian/copyright Source header' do
    stub_request(:get, "#{@sources}/debian/upstream/metadata").to_return(status: 404)
    stub_request(:get, "#{@salsa}/debian/upstream/metadata").to_return(status: 404)
    stub_request(:get, "#{@sources}/debian/copyright").to_return(status: 200, body: COPYRIGHT)

    @ecosystem.update_upstream_repository(@package)

    assert_equal 'https://github.com/rack/rack', @package.reload.metadata['upstream_repository_url']
    assert_equal 'debian/copyright', @package.metadata['upstream_repository_source']
  end

  test 'update_upstream_repository reads Repository when debian/upstream/metadata is not valid YAML' do
    stub_request(:get, "#{@sources}/debian/upstream/metadata").to_return(status: 200, body: "Repository: https://gitlab.com/rack/rack.git\nName: [broken\n")

    @ecosystem.update_upstream_repository(@package)

    assert_equal 'https://gitlab.com/rack/rack', @package.reload.metadata['upstream_repository_url']
  end

  test 'update_upstream_repository reads a continued Source field and skips urls that are not repositories' do
    stub_request(:get, "#{@sources}/debian/upstream/metadata").to_return(status: 404)
    stub_request(:get, "#{@salsa}/debian/upstream/metadata").to_return(status: 404)
    stub_request(:get, "#{@sources}/debian/copyright").to_return(status: 200, body: <<~TEXT)
      Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
      Source: https://rack.github.io/
       https://github.com/rack/rack/releases
    TEXT

    @ecosystem.update_upstream_repository(@package)

    assert_equal 'https://github.com/rack/rack', @package.reload.metadata['upstream_repository_url']
  end

  test 'update_upstream_repository marks the version checked when no packaging file names a repository' do
    stub_request(:get, /sources\.debian\.org|salsa\.debian\.org/).to_return(status: 404)

    @ecosystem.update_upstream_repository(@package)

    assert_nil @package.reload.metadata['upstream_repository_url']
    assert_equal '3.1.20-0+deb13u2', @package.metadata['upstream_repository_checked']
  end

  test 'update_upstream_repository drops a packaging value that the new version no longer has' do
    @package.update!(homepage: 'https://github.com/rack/rack-homepage',
                     metadata: { 'component' => 'main', 'upstream_repository_url' => 'https://github.com/old/rack', 'upstream_repository_source' => 'debian/copyright' })
    stub_request(:get, /sources\.debian\.org|salsa\.debian\.org/).to_return(status: 404)

    @ecosystem.update_upstream_repository(@package)

    assert_equal 'https://github.com/rack/rack-homepage', @package.reload.metadata['upstream_repository_url']
    assert_equal 'homepage', @package.metadata['upstream_repository_source']
  end

  test 'update_upstream_repository raises on a server error without marking the version checked' do
    stub_request(:get, "#{@sources}/debian/upstream/metadata").to_return(status: 503)

    assert_raises(Ecosystem::Deb::PackagingFileError) { @ecosystem.update_upstream_repository(@package) }
    assert_nil @package.reload.metadata['upstream_repository_checked']
  end

  test 'update_upstream_repository encodes an epoch in the sources.debian.org path' do
    @package.update!(latest_release_number: '2:9.1.1230-2')
    stub_request(:get, 'https://sources.debian.org/data/main/r/ruby-rack/2%3A9.1.1230-2/debian/upstream/metadata').to_return(status: 200, body: UPSTREAM_METADATA)

    @ecosystem.update_upstream_repository(@package)

    assert_equal 'https://github.com/rack/rack', @package.reload.metadata['upstream_repository_url']
  end

  test 'ubuntu reads the packaging files from salsa only' do
    registry = Registry.create!(name: 'ubuntu-24.04', version: '24.04', url: 'https://launchpad.net/ubuntu/noble', ecosystem: 'ubuntu', metadata: { 'codename' => 'noble' })
    package = registry.packages.create!(name: 'ruby-rack', ecosystem: 'ubuntu', latest_release_number: '3.0.8-2',
                                        repository_url: 'https://salsa.debian.org/ruby-team/ruby-rack', metadata: { 'component' => 'universe' })
    stub_request(:get, "#{@salsa}/debian/upstream/metadata").to_return(status: 200, body: UPSTREAM_METADATA)

    registry.ecosystem_instance.update_upstream_repository(package)

    assert_equal 'https://github.com/rack/rack', package.reload.metadata['upstream_repository_url']
    assert_not_requested :get, /sources\.debian\.org/
  end

  test 'merge_existing_metadata keeps a packaging value and the checked version over the homepage' do
    existing = { 'component' => 'main', 'upstream_repository_url' => 'https://github.com/rack/rack',
                 'upstream_repository_source' => 'debian/upstream/metadata', 'upstream_repository_checked' => '1.0-1' }
    merged = @ecosystem.merge_existing_metadata(existing, { component: 'main', upstream_repository_url: 'https://github.com/other/rack', upstream_repository_source: 'homepage' })

    assert_equal 'https://github.com/rack/rack', merged['upstream_repository_url']
    assert_equal 'debian/upstream/metadata', merged['upstream_repository_source']
    assert_equal '1.0-1', merged['upstream_repository_checked']
  end

  test 'merge_existing_metadata replaces a homepage value with the new homepage' do
    existing = { 'upstream_repository_url' => 'https://github.com/old/rack', 'upstream_repository_source' => 'homepage' }

    assert_not @ecosystem.merge_existing_metadata(existing, { component: 'main' }).key?('upstream_repository_url')
  end

  test 'after_package_synced enqueues the worker until the latest version is checked' do
    assert_difference -> { UpdateUpstreamRepositoryWorker.jobs.size }, 1 do
      @ecosystem.after_package_synced(@package)
    end

    @package.update!(metadata: @package.metadata.merge('upstream_repository_checked' => @package.latest_release_number))
    assert_no_difference -> { UpdateUpstreamRepositoryWorker.jobs.size } do
      @ecosystem.after_package_synced(@package)
    end
  end

  test 'a sync keeps the upstream repository found in the packaging files' do
    @package.update!(metadata: { 'component' => 'main', 'upstream_repository_url' => 'https://github.com/rack/rack',
                                 'upstream_repository_source' => 'debian/upstream/metadata', 'upstream_repository_checked' => '3.1.20-0+deb13u2' })
    @ecosystem.stubs(:fetch_package_metadata).returns({ name: 'ruby-rack', version: '3.1.20-0+deb13u2', homepage: 'https://rack.github.io/',
                                                         repository_url: 'https://salsa.debian.org/ruby-team/ruby-rack', metadata: { component: 'main', priority: 'optional' } })
    @registry.stubs(:ecosystem_instance).returns(@ecosystem)
    Package.any_instance.stubs(:update_repo_metadata_async)

    assert_no_difference -> { UpdateUpstreamRepositoryWorker.jobs.size } do
      @registry.sync_package('ruby-rack')
    end

    metadata = @package.reload.metadata
    assert_equal 'https://github.com/rack/rack', metadata['upstream_repository_url']
    assert_equal 'debian/upstream/metadata', metadata['upstream_repository_source']
    assert_equal 'optional', metadata['priority']
  end

  test 'the worker updates the package' do
    stub_request(:get, "#{@sources}/debian/upstream/metadata").to_return(status: 200, body: UPSTREAM_METADATA)

    UpdateUpstreamRepositoryWorker.new.perform(@package.id)

    assert_equal 'https://github.com/rack/rack', @package.reload.metadata['upstream_repository_url']
  end

  test 'the worker ignores packages from ecosystems without upstream repositories' do
    registry = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    package = registry.packages.create!(name: 'rand', ecosystem: 'cargo')

    assert_nothing_raised { UpdateUpstreamRepositoryWorker.new.perform(package.id) }
    assert_nothing_raised { UpdateUpstreamRepositoryWorker.new.perform(0) }
  end
end
