
require "test_helper"

class ClojarsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'clojars.org', url: 'https://repo.clojars.org', ecosystem: 'clojars')
    @ecosystem = Ecosystem::Clojars.new(@registry)
    @package = Package.new(ecosystem: 'clojars', name: 'missionary')
    @version = @package.versions.build(number: 'b.26')
    @maintainer = @registry.maintainers.build(login: 'foo', uuid: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://clojars.org/missionary/"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, "https://clojars.org/missionary/versions/b.26"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.jar"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://cljdoc.org/d/missionary/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "https://cljdoc.org/d/missionary/b.26"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://clojars.org/missionary/"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:clojars/missionary'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:clojars/missionary@b.26'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://repo.clojars.org/all-poms.txt")
      .to_return({ status: 200, body: file_fixture('clojars/all-poms.txt') })
    all_package_names = @ecosystem.all_package_names

    assert_equal all_package_names.length, 29151
    assert_equal all_package_names.last, 'zyzanie'
  end

  test 'recently_updated_package_names' do
    travel_to Time.utc(2026, 11, 14, 12) do
      stub_request(:get, 'https://clojars.org/api/release-feed')
        .with(query: {from: '2026-11-13T12:00:00.000Z'}, headers: {'Accept' => 'application/json'})
        .to_return(status: 200, body: file_fixture('clojars/release-feed.json'))

      assert_equal ['org.example/tool', 'missionary'], @ecosystem.recently_updated_package_names
      assert_not_requested(:get, 'https://clojars.org/')
    end
  end

  test 'recent sync continues from its saved cursor through short and empty pages' do
    travel_to Time.utc(2026, 11, 14, 12) do
      @registry.metadata = {unrelated: 'keep'}
      @registry.save!
      first = stub_request(:get, 'https://clojars.org/api/release-feed')
        .with(query: {from: '2026-11-13T12:00:00.000Z'})
        .to_return(status: 200, body: file_fixture('clojars/release-feed.json'))
      second = stub_request(:get, 'https://clojars.org/api/release-feed')
        .with(query: {from: '2026-11-14T11:59:00.000Z'})
        .to_return(status: 200, body: {
          next_from: '2026-11-14T12:00:01.000Z',
          releases: [{group_id: 'another', artifact_id: 'another', version: '1.0', released_at: '2026-11-14T12:00:01.000Z'}]
        }.to_json)
      third = stub_request(:get, 'https://clojars.org/api/release-feed')
        .with(query: {from: '2026-11-14T12:00:01.000Z'})
        .to_return(status: 200, body: {next_from: '2026-11-14T12:00:01.000Z', releases: []}.to_json)
      SyncPackageWorker.clear

      @registry.sync_recently_updated_packages_async
      assert_equal '2026-11-14T11:59:00.000Z', @registry.reload.metadata.dig('clojars_release_feed', 'from')
      @registry.sync_recently_updated_packages_async
      @registry.sync_recently_updated_packages_async

      assert_equal ['missionary', 'org.example/tool', 'another'].map { |name| [@registry.id, name, true] }, SyncPackageWorker.jobs.map { |job| job['args'] }
      assert_equal '2026-11-14T12:00:01.000Z', @registry.reload.metadata.dig('clojars_release_feed', 'from')
      assert_equal 'keep', @registry.metadata['unrelated']
      assert_requested first, times: 1
      assert_requested second, times: 1
      assert_requested third, times: 1
    end
  ensure
    SyncPackageWorker.clear
  end

  test 'recent sync enqueues every release beyond the registry name limit and spreads the rate budget' do
    travel_to Time.utc(2026, 11, 14, 12) do
      @registry.rate_limit = 1
      @registry.save!
      releases = 105.times.map { |i| {group_id: 'org.example', artifact_id: "tool-#{i}", version: '1.0'} }
      stub_request(:get, 'https://clojars.org/api/release-feed')
        .with(query: {from: '2026-11-13T12:00:00.000Z'})
        .to_return(status: 200, body: {next_from: '2026-11-14T12:00:00.000Z', releases: releases}.to_json)
      SyncPackageWorker.clear

      @registry.sync_recently_updated_packages_async(period: 10.seconds)

      jobs = SyncPackageWorker.jobs
      assert_equal 105, jobs.length
      assert_equal [@registry.id, 'org.example/tool-104', true], jobs.last['args']
      assert_equal Time.current.to_f + 100, jobs.last['at']
      assert_equal '2026-11-14T12:00:00.000Z', @registry.reload.metadata.dig('clojars_release_feed', 'from')
    end
  ensure
    SyncPackageWorker.clear
  end

  test 'recent sync advances through snapshot-only pages without queuing packages' do
    @registry.metadata = {'clojars_release_feed' => {'from' => '2026-11-14T11:00:00.000Z'}}
    @registry.save!
    stub_request(:get, 'https://clojars.org/api/release-feed')
      .with(query: {from: '2026-11-14T11:00:00.000Z'})
      .to_return(status: 200, body: {
        next_from: '2026-11-14T12:00:00.000Z',
        releases: [{group_id: 'org.example', artifact_id: 'tool', version: '1.0-SNAPSHOT'}]
      }.to_json)
    SyncPackageWorker.clear

    @registry.sync_recently_updated_packages_async

    assert_empty SyncPackageWorker.jobs
    assert_equal '2026-11-14T12:00:00.000Z', @registry.reload.metadata.dig('clojars_release_feed', 'from')
  ensure
    SyncPackageWorker.clear
  end

  test 'recent sync retains its cursor if jobs are not fully queued' do
    @registry.metadata = {'clojars_release_feed' => {'from' => '2026-11-13T12:00:00.000Z'}}
    @registry.save!
    stub_request(:get, 'https://clojars.org/api/release-feed')
      .with(query: {from: '2026-11-13T12:00:00.000Z'})
      .to_return(status: 200, body: file_fixture('clojars/release-feed.json'))
    SyncPackageWorker.expects(:set).returns(stub(perform_bulk: [nil, nil]))

    assert_raises(RuntimeError) { @registry.sync_recently_updated_packages_async }

    assert_equal '2026-11-13T12:00:00.000Z', @registry.reload.metadata.dig('clojars_release_feed', 'from')
  end

  test 'recent sync retains its cursor on unavailable or invalid feeds' do
    @registry.metadata = {'clojars_release_feed' => {'from' => '2026-11-13T12:00:00.000Z'}}
    @registry.save!
    responses = [
      {status: 503, body: 'Service unavailable'},
      {status: 200, body: '{'},
      {status: 200, body: {next_from: '2026-11-14T12:00:00.000Z', releases: {}}.to_json},
      {status: 200, body: {next_from: '2026-11-12T12:00:00.000Z', releases: []}.to_json},
      {status: 200, body: {next_from: '2026-11-13T12:00:00.000Z', releases: [{group_id: 'x', artifact_id: 'x', version: '1'}]}.to_json},
      {status: 200, body: {next_from: '2026-11-14T12:00:00.000Z', releases: [{}]}.to_json}
    ]
    responses.each do |response|
      stub_request(:get, 'https://clojars.org/api/release-feed')
        .with(query: {from: '2026-11-13T12:00:00.000Z'})
        .to_return(response)

      assert_raises(StandardError) { @registry.sync_recently_updated_packages_async }
      assert_equal '2026-11-13T12:00:00.000Z', @registry.reload.metadata.dig('clojars_release_feed', 'from')
    end
  end

  test 'package_metadata' do
    stub_request(:get, "https://clojars.org/api/artifacts/missionary")
      .to_return({ status: 200, body: file_fixture('clojars/missionary') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('clojars/maven-metadata.xml') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom'), headers: { 'last-modified' => 'Tue, 11 Jan 2022 14:34:47 GMT' }  })
    package_metadata = @ecosystem.package_metadata('missionary')

    assert_equal package_metadata[:name], "missionary"
    assert_equal package_metadata[:description], "A functional effect and streaming system for clojure and clojurescript."
    assert_equal package_metadata[:homepage], "https://github.com/leonoel/missionary"
    assert_equal package_metadata[:licenses], "Eclipse Public License"
    assert_equal package_metadata[:repository_url], "https://github.com/leonoel/missionary"
    assert_equal package_metadata[:downloads], 5990
    assert_equal package_metadata[:downloads_period], "total"
    assert_equal package_metadata[:namespace], "missionary"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('clojars/maven-metadata.xml') })
    stub_request(:get, "https://clojars.org/api/artifacts/missionary")
      .to_return({ status: 200, body: file_fixture('clojars/missionary') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom'), headers: { 'last-modified' => 'Tue, 11 Jan 2022 14:34:47 GMT' }  })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.25/missionary-b.25.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.25.pom'), headers: { 'last-modified' => 'Fri, 24 Dec 2021 08:31:43 GMT' }  })

    package_metadata = @ecosystem.package_metadata('missionary')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"b.26", :published_at=>'2022-01-11 14:34:47 +0000', :licenses=>"Eclipse Public License"},
      {:number=>"b.25", :published_at=>'2021-12-24 08:31:43 +0000', :licenses=>"Eclipse Public License"},
  ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom') })

    dependencies_metadata = @ecosystem.dependencies_metadata('missionary', 'b.26', {})

    assert_equal [
      {:package_name=>"org.clojure:clojure", :requirements=>"1.10.3", :kind=>nil, :ecosystem=>"clojars"},
      {:package_name=>"org.clojure:clojurescript", :requirements=>"1.10.879", :kind=>nil, :ecosystem=>"clojars"},
      {:package_name=>"org.reactivestreams:reactive-streams", :requirements=>"1.0.3", :kind=>nil, :ecosystem=>"clojars"},
      {:package_name=>"cloroutine", :requirements=>"10", :kind=>nil, :ecosystem=>"clojars"}
    ], dependencies_metadata
  end

  test 'maintainer_url' do
    assert_equal @ecosystem.maintainer_url(@maintainer), "https://clojars.org/users/foo"
  end

  test 'check_status reuses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('clojars/maven-metadata.xml') })
    stub_request(:get, "https://clojars.org/api/artifacts/missionary")
      .to_return({ status: 200, body: file_fixture('clojars/missionary') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom'), headers: { 'last-modified' => 'Tue, 11 Jan 2022 14:34:47 GMT' } })

    # Fetch metadata first to populate the cache
    @ecosystem.package_metadata('missionary')

    # check_status should reuse cached data
    status = @ecosystem.check_status(@package)
    assert_nil status

    # The registry URL should NOT have been hit
    assert_not_requested(:get, "https://clojars.org/missionary/")
    assert_not_requested(:head, "https://clojars.org/missionary/")
  end

  test 'pom downloads are memoized across calls' do
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/maven-metadata.xml")
      .to_return({ status: 200, body: file_fixture('clojars/maven-metadata.xml') })
    stub_request(:get, "https://clojars.org/api/artifacts/missionary")
      .to_return({ status: 200, body: file_fixture('clojars/missionary') })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.26.pom'), headers: { 'last-modified' => 'Tue, 11 Jan 2022 14:34:47 GMT' } })
    stub_request(:get, "https://repo.clojars.org/missionary/missionary/b.25/missionary-b.25.pom")
      .to_return({ status: 200, body: file_fixture('clojars/missionary-b.25.pom'), headers: { 'last-modified' => 'Fri, 24 Dec 2021 08:31:43 GMT' } })

    # package_metadata downloads b.26 POM
    package_metadata = @ecosystem.package_metadata('missionary')
    # versions_metadata also needs b.26 POM - should be cached
    @ecosystem.versions_metadata(package_metadata)

    # b.26 POM should only have been fetched once despite being needed by both methods
    assert_requested(:get, "https://repo.clojars.org/missionary/missionary/b.26/missionary-b.26.pom", times: 1)
  end
end
