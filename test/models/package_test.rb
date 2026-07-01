require "test_helper"

class PackageTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:registry)
    should have_many(:dependencies)
    should have_many(:versions)
  end

  context 'validations' do
    should validate_presence_of(:registry_id)
    should validate_presence_of(:name)
    should validate_presence_of(:ecosystem)
    should validate_uniqueness_of(:name).scoped_to(:registry_id)
  end

  setup do
    @registry = Registry.create(default: true, name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @package = @registry.packages.create(name: 'foo', ecosystem: @registry.ecosystem, licenses: 'mit')
    @version = @package.versions.create(number: '1.0.0', published_at: 1.month.ago)
    @version2 = @package.versions.create(number: '2.0.0', published_at: 1.week.ago)
  end

  test 'update_details' do
    @package.expects(:normalize_licenses).returns(true)
    @package.expects(:set_latest_release_published_at).returns(true)
    @package.expects(:set_latest_release_number).returns(true)
    @package.update_details
  end

  test 'normalize_licenses' do
    @package.normalize_licenses
    assert_equal @package.normalized_licenses, ["MIT"]
  end

  test 'spdx_license does not match other to GPL' do
    package = @registry.packages.create(name: 'test_other', ecosystem: @registry.ecosystem, licenses: 'other')
    assert_equal [], package.spdx_license
  end

  test 'spdx_license does not match unknown to any license' do
    package = @registry.packages.create(name: 'test_unknown', ecosystem: @registry.ecosystem, licenses: 'unknown')
    assert_equal [], package.spdx_license
  end

  test 'normalize_licenses returns Other for unrecognized license strings' do
    package = @registry.packages.create(name: 'test_other', ecosystem: @registry.ecosystem, licenses: 'other')
    package.normalize_licenses
    assert_equal ["Other"], package.normalized_licenses
  end

  test 'normalize_licenses handles compound OR licenses' do
    package = @registry.packages.create(name: 'test_or', ecosystem: @registry.ecosystem, licenses: 'Apache-2.0 OR BSD-3-Clause')
    package.normalize_licenses
    assert_equal ["Apache-2.0", "BSD-3-Clause"], package.normalized_licenses
  end

  test 'normalize_licenses handles compound AND licenses' do
    package = @registry.packages.create(name: 'test_and', ecosystem: @registry.ecosystem, licenses: 'Apache-2.0 AND MIT')
    package.normalize_licenses
    assert_equal ["Apache-2.0", "MIT"], package.normalized_licenses
  end

  test 'normalize_licenses handles parenthesized compound licenses' do
    package = @registry.packages.create(name: 'test_parens', ecosystem: @registry.ecosystem, licenses: '(Apache-2.0 OR BSD-3-Clause)')
    package.normalize_licenses
    assert_equal ["Apache-2.0", "BSD-3-Clause"], package.normalized_licenses
  end

  test 'normalize_licenses parses valid SPDX expressions directly' do
    package = @registry.packages.create(name: 'test_spdx', ecosystem: @registry.ecosystem, licenses: 'EPL-2.0 OR GPL-2.0 WITH Classpath-exception-2.0')
    package.normalize_licenses
    assert_equal ["EPL-2.0", "GPL-2.0"], package.normalized_licenses
  end

  test 'normalize_licenses handles license names containing commas' do
    package = @registry.packages.create(name: 'test_comma', ecosystem: @registry.ecosystem, licenses: 'GNU General Public License, version 2 with the GNU Classpath Exception')
    package.normalize_licenses
    assert_equal ["GPL-2.0-with-classpath-exception"], package.normalized_licenses
  end

  test 'normalize_licenses ignores orphaned version fragments' do
    package = @registry.packages.create(name: 'test_ver', ecosystem: @registry.ecosystem, licenses: 'Some License, Version 2.0')
    package.normalize_licenses
    assert_not_includes package.normalized_licenses, "libpng-2.0"
  end

  test 'normalize_licenses still handles Apache License, Version 2.0' do
    package = @registry.packages.create(name: 'test_apache', ecosystem: @registry.ecosystem, licenses: 'Apache License, Version 2.0')
    package.normalize_licenses
    assert_equal ["Apache-2.0"], package.normalized_licenses
  end

  test 'set_latest_release_published_at' do
    @package.set_latest_release_published_at
    assert_equal @package.latest_release_published_at, @version2.published_at
  end

  test 'set_latest_release_number' do
    @package.set_latest_release_number
    assert_equal @package.latest_release_number, '2.0.0'
  end

  test 'install_command' do
    assert_equal @package.install_command, 'gem install foo -s https://rubygems.org'
  end

  test 'repo_funding_links splits comma separated github usernames' do
    @package.update(
      repo_metadata: {
        'metadata' => {
          'funding' => {
            'github' => 'foo, bar, baz'
          }
        }
      }
    )

    assert_equal [
      'https://github.com/sponsors/foo',
      'https://github.com/sponsors/bar',
      'https://github.com/sponsors/baz'
    ], @package.repo_funding_links
  end

  test 'repo_funding_links handles github username arrays' do
    @package.update(
      repo_metadata: {
        'metadata' => {
          'funding' => {
            'github' => ['foo', 'bar']
          }
        }
      }
    )

    assert_equal [
      'https://github.com/sponsors/foo',
      'https://github.com/sponsors/bar'
    ], @package.repo_funding_links
  end

  test 'repo_funding_links limits github usernames to four' do
    @package.update(
      repo_metadata: {
        'metadata' => {
          'funding' => {
            'github' => 'foo, bar, baz, qux, quux'
          }
        }
      }
    )

    assert_equal [
      'https://github.com/sponsors/foo',
      'https://github.com/sponsors/bar',
      'https://github.com/sponsors/baz',
      'https://github.com/sponsors/qux'
    ], @package.repo_funding_links
  end

  test 'registry_url' do
    assert_equal @package.registry_url, 'https://rubygems.org/gems/foo'
  end

  test 'documentation_url' do
    assert_equal @package.documentation_url, "http://www.rubydoc.info/gems/foo/"
  end

  test 'purl' do
    assert_equal @package.purl, "pkg:gem/foo"
  end

  test 'Package.purl class method finds package by single purl' do
    result = Package.purl('pkg:gem/foo')
    assert_includes result, @package
  end

  test 'Package.purl class method finds packages by multiple purls' do
    bar_package = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem)

    result = Package.purl(['pkg:gem/foo', 'pkg:gem/bar'])

    assert_includes result, @package
    assert_includes result, bar_package
  end

  test 'Package.purl class method returns none for empty array' do
    result = Package.purl([])
    assert_equal 0, result.count
  end

  test 'Package.purl class method skips invalid purls' do
    result = Package.purl(['pkg:gem/foo', 'invalid-purl'])
    assert_includes result, @package
  end

  test 'Package.purl class method handles docker purl without namespace' do
    docker_registry = Registry.create(name: 'hub.docker.com', url: 'https://hub.docker.com', ecosystem: 'docker')
    docker_package = docker_registry.packages.create(name: 'library/python', ecosystem: 'docker', namespace: 'library')

    result = Package.purl('pkg:docker/python')

    assert_includes result, docker_package
  end

  test 'Package.purl class method handles github purl via repository_url' do
    @package.update(repository_url: 'https://github.com/rails/rails')

    result = Package.purl('pkg:github/rails/rails')

    assert_includes result, @package
  end

  test 'Package.purl class method handles npm scoped packages' do
    npm_registry = Registry.create(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    scoped_package = npm_registry.packages.create(name: '@babel/core', ecosystem: 'npm', namespace: 'babel')

    result = Package.purl('pkg:npm/@babel/core')

    assert_includes result, scoped_package
  end

  test 'sync_async enqueues UpdatePackageWorker' do
    @package.update(last_synced_at: 2.days.ago)
    UpdatePackageWorker.expects(:perform_async).with(@package.id).once
    @package.sync_async
  end

  test 'sync_async skips recently synced packages' do
    @package.update(last_synced_at: 1.hour.ago)
    UpdatePackageWorker.expects(:perform_async).never
    @package.sync_async
  end

  test 'sync_async skips batch ecosystem packages' do
    batch_registry = Registry.create(name: 'nixpkgs-unstable', url: 'https://channels.nixos.org/nixos-unstable', ecosystem: 'nixpkgs', version: 'unstable')
    batch_package = batch_registry.packages.create(name: 'hello', ecosystem: 'nixpkgs', last_synced_at: 2.days.ago)
    UpdatePackageWorker.expects(:perform_async).never
    batch_package.sync_async
  end

  test 'status reader returns nil for active packages' do
    @package.update_column(:status, 'active')
    assert_nil @package.reload.status
  end

  test 'status reader returns nil for nil status' do
    @package.update_column(:status, nil)
    assert_nil @package.reload.status
  end

  test 'status reader returns removed for removed packages' do
    @package.update_column(:status, 'removed')
    assert_equal 'removed', @package.reload.status
  end

  test 'updating package status to removed marks versions removed' do
    @package.update!(status: 'removed')

    assert_equal ['removed'], @package.versions.reload.pluck(:status).uniq
  end

  test 'updating package status to another inactive status does not mark versions removed' do
    @version.update!(status: 'yanked')

    @package.update!(status: 'unpublished')

    assert_equal ['yanked', nil], @package.versions.order(:number).pluck(:status)
  end

  test 'check_status sets active when ecosystem returns nil' do
    @package.registry.ecosystem_instance.expects(:check_status).with(@package).returns(nil)
    @package.check_status
    assert_equal 'active', @package.read_attribute(:status)
    assert_not_nil @package.last_synced_at
  end

  test 'check_status sets removed when ecosystem returns removed' do
    @package.registry.ecosystem_instance.expects(:check_status).with(@package).returns('removed')
    @package.check_status
    assert_equal 'removed', @package.read_attribute(:status)
    assert_not_nil @package.last_synced_at
  end

  test 'check_status always updates last_synced_at' do
    @package.update_column(:status, 'active')
    @package.update_column(:last_synced_at, 2.months.ago)
    @package.registry.ecosystem_instance.expects(:check_status).with(@package).returns(nil)
    @package.check_status
    assert @package.last_synced_at > 1.minute.ago
  end

  test 'dependent_packages returns packages that depend on this package' do
    dependent = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem)
    dep_version = dependent.versions.create(number: '1.0.0')
    dep_version.dependencies.create(package_id: @package.id, package_name: 'foo', ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')

    result = @package.dependent_packages
    assert_includes result, dependent
  end

  test 'latest_dependent_packages only includes packages with latest version dependency' do
    dependent = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem)
    old_version = dependent.versions.create(number: '1.0.0', latest: false)
    old_version.dependencies.create(package_id: @package.id, package_name: 'foo', ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')

    assert_empty @package.latest_dependent_packages

    new_version = dependent.versions.create(number: '2.0.0', latest: true)
    new_version.dependencies.create(package_id: @package.id, package_name: 'foo', ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')

    assert_includes @package.latest_dependent_packages, dependent
  end

  test 'dependent_package_kinds groups by dependency kind' do
    dependent = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem)
    dep_version = dependent.versions.create(number: '1.0.0')
    dep_version.dependencies.create(package_id: @package.id, package_name: 'foo', ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')
    dep_version.dependencies.create(package_id: @package.id, package_name: 'foo', ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'development')

    kinds = @package.dependent_package_kinds
    assert_equal 1, kinds['runtime']
    assert_equal 1, kinds['development']
  end

  test 'with_advisories scope' do
    package_with_advisories = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem, advisories: [{ 'id' => 'CVE-2024-1234' }])
    package_without_advisories = @registry.packages.create(name: 'baz', ecosystem: @registry.ecosystem, advisories: [])

    results = Package.with_advisories

    assert_includes results, package_with_advisories
    refute_includes results, package_without_advisories
    refute_includes results, @package
  end

  test 'as_live_event_json includes API fields' do
    json = @package.as_live_event_json

    assert_equal 'foo', json['name']
    assert_equal 'rubygems', json['ecosystem']
    assert_equal 'pkg:gem/foo', json['purl']
    assert_equal 'https://rubygems.org/gems/foo', json['registry_url']
    assert_equal 'gem install foo -s https://rubygems.org', json['install_command']
    assert json.key?('description')
    assert json.key?('repository_url')
    assert json.key?('latest_release_number')
    assert json.key?('status')
    refute json.key?('maintainers')
    refute json.key?('repo_metadata')
  end

  test 'live_event_payload for package.created' do
    payload = @package.live_event_payload(event: 'package.created')

    assert_equal 'package.created', payload[:event]
    assert_equal 'rubygems.org', payload[:registry]
    assert_equal 'https://packages.ecosyste.ms/api/v1/registries/rubygems.org', payload[:registry_url]
    assert_equal 'https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages/foo', payload[:package_url]
    assert_equal 'foo', payload[:package]['name']
    assert_equal 'pkg:gem/foo', payload[:package]['purl']
    refute payload.key?(:version)
  end

  test 'live_event_payload for version.created' do
    payload = @package.live_event_payload(event: 'version.created', version: @version)

    assert_equal 'version.created', payload[:event]
    assert_equal 'https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages/foo', payload[:package_url]
    assert_equal 'https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages/foo/versions/1.0.0', payload[:version_url]
    assert_equal 'foo', payload[:package]['name']
    assert_equal '1.0.0', payload[:version]['number']
    assert_equal 'pkg:gem/foo@1.0.0', payload[:version]['purl']
    assert payload[:version].key?('published_at')
    assert payload[:version].key?('download_url')
  end

  test 'live_event_payload encodes package name in url' do
    npm = Registry.create(default: true, name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    pkg = npm.packages.create(name: '@scope/pkg', ecosystem: 'npm')

    assert_equal 'https://packages.ecosyste.ms/api/v1/registries/npmjs.org/packages/%40scope%2Fpkg',
                 pkg.live_event_payload(event: 'package.created')[:package_url]
  end

  test 'emit_new_package_event calls LiveEvent.emit' do
    LiveEvent.stubs(:enabled?).returns(true)
    LiveEvent.expects(:emit).with(has_entry(:event, 'package.created'))
    @package.emit_new_package_event
  end

  test 'emit_new_package_event does nothing when LiveEvent disabled' do
    LiveEvent.stubs(:enabled?).returns(false)
    LiveEvent.expects(:emit).never
    @package.emit_new_package_event
  end

  test 'emit_new_version_events calls LiveEvent.emit with one event per version' do
    LiveEvent.stubs(:enabled?).returns(true)
    LiveEvent.expects(:emit).with do |events|
      events.length == 2 &&
        events.all? { |e| e[:event] == 'version.created' } &&
        events.map { |e| e[:version]['number'] } == ['1.0.0', '2.0.0']
    end
    @package.emit_new_version_events([@version, @version2])
  end

  test 'emit_new_version_events does nothing with empty array' do
    LiveEvent.stubs(:enabled?).returns(true)
    LiveEvent.expects(:emit).never
    @package.emit_new_version_events([])
  end

  test 'emit_new_version_events does nothing when LiveEvent disabled' do
    LiveEvent.stubs(:enabled?).returns(false)
    LiveEvent.expects(:emit).never
    @package.emit_new_version_events([@version])
  end

  test 'emit_new_package_event swallows payload errors' do
    LiveEvent.stubs(:enabled?).returns(true)
    @package.stubs(:as_live_event_json).raises(NoMethodError, 'boom')

    assert_nothing_raised { @package.emit_new_package_event }
  end

  test 'emit_new_version_events swallows payload errors' do
    LiveEvent.stubs(:enabled?).returns(true)
    @version.stubs(:as_live_event_json).raises(NoMethodError, 'boom')

    assert_nothing_raised { @package.emit_new_version_events([@version]) }
  end

  test 'update_top_dependent_packages does nothing below threshold' do
    @package.update_column(:dependent_packages_count, TopDependentPackage::THRESHOLD)
    @package.update_top_dependent_packages
    assert_empty @package.top_dependent_packages
  end

  test 'update_top_dependent_packages clears stale rows below threshold' do
    TopDependentPackage.create!(package_id: @package.id, sort: 'downloads', dependent_ids: [1, 2, 3], updated_at: Time.current)
    @package.update_column(:dependent_packages_count, 5)
    @package.update_top_dependent_packages
    assert_empty @package.top_dependent_packages.reload
  end

  test 'update_top_dependent_packages writes one row per sort above threshold' do
    deps = 3.times.map do |i|
      d = @registry.packages.create!(name: "dep#{i}", ecosystem: @registry.ecosystem,
                                      downloads: (i + 1) * 100,
                                      dependent_packages_count: 3 - i,
                                      dependent_repos_count: i,
                                      rankings: { 'average' => (i + 1).to_f })
      v = d.versions.create!(number: '1.0.0', latest: true)
      v.dependencies.create!(package_id: @package.id, package_name: @package.name, ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')
      d
    end

    @package.update_column(:dependent_packages_count, TopDependentPackage::THRESHOLD + 1)
    @package.update_top_dependent_packages

    rows = @package.top_dependent_packages.reload.index_by(&:sort)
    assert_equal TopDependentPackage::SORTS.keys.sort, rows.keys.sort

    assert_equal [deps[2].id, deps[1].id, deps[0].id], rows['downloads'].dependent_ids
    assert_equal [deps[0].id, deps[1].id, deps[2].id], rows['dependent_packages_count'].dependent_ids
    assert_equal [deps[2].id, deps[1].id, deps[0].id], rows['dependent_repos_count'].dependent_ids
    assert_equal [deps[0].id, deps[1].id, deps[2].id], rows['rank'].dependent_ids
  end

  test 'update_top_dependent_packages upserts on repeat' do
    dep = @registry.packages.create!(name: 'dep', ecosystem: @registry.ecosystem, downloads: 100)
    v = dep.versions.create!(number: '1.0.0', latest: true)
    v.dependencies.create!(package_id: @package.id, package_name: @package.name, ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')

    @package.update_column(:dependent_packages_count, TopDependentPackage::THRESHOLD + 1)
    @package.update_top_dependent_packages
    @package.update_top_dependent_packages

    assert_equal TopDependentPackage::SORTS.size, @package.top_dependent_packages.reload.count
  end
end
