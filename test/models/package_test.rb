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

  test 'with_advisories scope' do
    package_with_advisories = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem, advisories: [{ 'id' => 'CVE-2024-1234' }])
    package_without_advisories = @registry.packages.create(name: 'baz', ecosystem: @registry.ecosystem, advisories: [])

    results = Package.with_advisories

    assert_includes results, package_with_advisories
    refute_includes results, package_without_advisories
    refute_includes results, @package
  end
end
