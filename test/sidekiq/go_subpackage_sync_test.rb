require 'test_helper'

class GoSubpackageSyncTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 10, 2, 12)
    SyncPackageWorker.clear
    @registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go')
    @module_path = 'github.com/aws/aws-sdk-go-v2/service/s3'
    @repository_url = 'https://github.com/aws/aws-sdk-go-v2'
    @module = @registry.packages.create!(name: @module_path, ecosystem: 'go', status: 'active', repository_url: @repository_url, latest_release_number: 'v1.113.4', last_synced_at: 2.days.ago)
    @module.versions.create!(registry: @registry, number: 'v1.113.4', published_at: Time.utc(2026, 9, 24), latest: true)
    stub_module
  end

  teardown do
    SyncPackageWorker.clear
    travel_back
  end

  test 'module sync queues only active stale subpackages of the exact module' do
    types = create_subpackage('types')
    nested = create_subpackage('internal/encoding/types', repository_url: @repository_url.upcase)
    create_subpackage('current', latest_release_number: 'v1.114.0')
    create_subpackage('removed', status: 'removed')
    create_subpackage('other-module', metadata: { 'module_path' => 'github.com/aws/aws-sdk-go-v2' })
    create_subpackage('other-case', metadata: { 'module_path' => @module_path.upcase })
    create_subpackage('other-repo', repository_url: 'https://github.com/example/other')
    create_subpackage('missing-repo', repository_url: nil)

    SyncPackageWorker.new.perform(@registry.id, @module_path, true)

    assert_equal 'v1.114.0', @module.reload.latest_release_number
    assert_equal [types.name, nested.name].sort, queued_names.sort
    assert SyncPackageWorker.jobs.all? { |job| job['args'] == [@registry.id, job['args'][1], true] }
    assert_equal 'v1.113.4', types.reload.latest_release_number

    stub_subpackage(types)
    SyncPackageWorker.clear
    SyncPackageWorker.new.perform(@registry.id, types.name, true)

    assert_equal 'v1.114.0', types.reload.latest_release_number
    assert_equal ['v1.114.0'], types.versions.where(latest: true).pluck(:number)
    assert_empty SyncPackageWorker.jobs
  end

  test 'unchanged module latest does not enqueue another refresh' do
    create_subpackage('types')
    SyncPackageWorker.new.perform(@registry.id, @module_path, true)
    assert_equal 1, SyncPackageWorker.jobs.size
    SyncPackageWorker.clear

    SyncPackageWorker.new.perform(@registry.id, @module_path, true)

    assert_empty SyncPackageWorker.jobs
  end

  test 'version-only updates also refresh subpackages' do
    types = create_subpackage('types')

    UpdateVersionsWorker.new.perform(@module.id)

    assert_equal 'v1.114.0', @module.reload.latest_release_number
    assert_equal [types.name], queued_names
  end

  test 'refreshes retain all candidates while respecting the registry budget' do
    @registry.update!(metadata: { 'rate_limit' => 0.01 })
    names = 31.times.map { |i| create_subpackage("types#{i}").name }

    SyncPackageWorker.new.perform(@registry.id, @module_path, true)

    assert_equal names.sort, queued_names.sort
    times = SyncPackageWorker.jobs.map { |job| job.fetch('at') }.sort
    assert_equal Time.current.to_f, times.first
    assert times.each_cons(2).all? { |left, right| right - left >= 100 }
    assert_equal 9, times.count { |time| time < Time.current.to_f + 15.minutes }
  end

  test 'unthrottled registries schedule at most twenty-five refreshes per fifteen minutes' do
    26.times { |i| create_subpackage("types#{i}") }

    SyncPackageWorker.new.perform(@registry.id, @module_path, true)

    times = SyncPackageWorker.jobs.map { |job| job.fetch('at') }.sort
    assert_equal 26, times.size
    assert_equal 25, times.count { |time| time < Time.current.to_f + 15.minutes }
    assert_equal Time.current.to_f + 15.minutes, times.last
  end

  test 'a budget below one job per period delays remaining refreshes' do
    @registry.update!(metadata: { 'rate_limit' => 1.0 / 1800 })
    2.times { |i| create_subpackage("types#{i}") }

    SyncPackageWorker.new.perform(@registry.id, @module_path, true)

    times = SyncPackageWorker.jobs.map { |job| job.fetch('at') }.sort
    assert_equal 2, times.size
    assert_in_delta 1800, times.last - times.first
  end

  test 'modules without repository URLs do not search for subpackages' do
    create_subpackage('types')
    stub_module(repository_url: nil)

    SyncPackageWorker.new.perform(@registry.id, @module_path, true)

    assert_equal 'v1.114.0', @module.reload.latest_release_number
    assert_nil @module.repository_url
    assert_empty SyncPackageWorker.jobs
  end

  test 'syncing a subpackage does not refresh its descendants' do
    package = create_subpackage('types')
    create_subpackage('types/nested', metadata: { 'module_path' => package.name })
    stub_subpackage(package)

    SyncPackageWorker.new.perform(@registry.id, package.name, true)

    assert_equal 'v1.114.0', package.reload.latest_release_number
    assert_empty SyncPackageWorker.jobs
  end

  def queued_names
    SyncPackageWorker.jobs.map { |job| job.fetch('args')[1] }
  end

  def create_subpackage(suffix, **attributes)
    package = @registry.packages.create!({ name: "#{@module_path}/#{suffix}", ecosystem: 'go', status: 'active', repository_url: @repository_url, metadata: { 'module_path' => @module_path }, latest_release_number: 'v1.113.4', last_synced_at: 1.hour.ago }.merge(attributes))
    package.versions.create!(registry: @registry, number: package.latest_release_number, published_at: Time.utc(2026, 9, 24), latest: true)
    package
  end

  def stub_module(repository_url: @repository_url)
    stub_request(:get, "https://pkg.go.dev/v1beta/module/#{@module_path}?licenses=true")
      .to_return(body: { path: @module_path, version: 'v1.114.0', repoUrl: repository_url, licenses: [{ types: ['Apache-2.0'] }] }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/package/#{@module_path}")
      .to_return(body: { modulePath: @module_path, version: 'v1.114.0', path: @module_path, synopsis: 'Package s3 provides the API client for Amazon Simple Storage Service.' }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/#{@module_path}?limit=1000")
      .to_return(body: { items: [
        { modulePath: @module_path, version: 'v1.114.0', commitTime: '2026-09-30T18:31:54Z', retracted: false, deprecated: false },
        { modulePath: @module_path, version: 'v1.113.4', commitTime: '2026-09-24T18:17:37Z', retracted: false, deprecated: false }
      ] }.to_json)
    %w[v1.113.4 v1.114.0].each do |version|
      stub_request(:get, "https://proxy.golang.org/cached-only/#{@module_path}/@v/#{version}.mod")
        .to_return(body: "module #{@module_path}\n\ngo 1.24\n\nrequire github.com/aws/smithy-go v1.23.1\n")
    end
  end

  def stub_subpackage(package)
    stub_request(:get, "https://pkg.go.dev/v1beta/module/#{package.name}?licenses=true")
      .to_return(status: 400, body: { code: 400, message: "#{package.name} is a package, not a module" }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/package/#{package.name}")
      .to_return(body: { modulePath: @module_path, version: 'v1.114.0', path: package.name, synopsis: 'Package types provides API types.' }.to_json)
  end
end
