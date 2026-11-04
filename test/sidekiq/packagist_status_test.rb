require 'test_helper'

class PackagistStatusTest < ActiveSupport::TestCase
  setup do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    LiveEvent.stubs(:enabled?).returns(false)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    @time = Time.current.change(usec: 0)
    @registry = Registry.create!(name: 'packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @package = @registry.packages.create!(name: 'psr/log', ecosystem: 'packagist', status: 'active', last_synced_at: 2.days.ago)
    @version = @package.versions.create!(number: '1.0.0', metadata: {'custom' => true})
    @enrichment_url = 'https://packagist.org/packages/psr/log.json'
    @tagged_url = 'https://repo.packagist.org/p2/psr/log.json'
    @enrichment = JSON.parse(file_fixture('packagist/log.json.1').read)
    stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
    stub_request(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
      .to_return(body: {packages: {'psr/log' => []}}.to_json)
    tagged
  end

  %w[sync by_id versions changes refresh status].each do |path|
    test "#{path} retains replacement names and clears withdrawn abandonment despite cached enrichment" do
      @enrichment['package']['abandoned'] = 'vendor/old-replacement'
      stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
      tagged(abandoned: 'vendor/replacement')
      perform(path)
      assert_equal 'abandoned', @package.reload[:status]
      assert_equal 'vendor/replacement', @package.metadata['abandoned']
      assert_nil @version.reload.status
      assert_equal '1.0.0', @package.latest_release_number

      tagged(abandoned: true)
      perform(path)
      assert_equal 'abandoned', @package.reload[:status]
      assert_equal true, @package.metadata['abandoned']

      tagged
      perform(path)
      assert_equal 'active', @package.reload[:status]
      assert_equal false, @package.metadata['abandoned']
      assert_equal [@version.id], @package.versions.pluck(:id)
      assert_equal true, @version.reload.metadata['custom']
      assert_requested(:get, @enrichment_url, times: 1)
      assert_not_requested(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
    end

    test "#{path} removes full-package absence and recovers only current releases" do
      absent = @package.versions.create!(number: '2.0.0')
      @package.update_details
      ids = @package.versions.order(:id).pluck(:id)
      stub_request(:get, @enrichment_url).to_return(status: 404)

      perform(path)

      assert_equal 'removed', @package.reload[:status]
      assert_equal ['removed'], @package.versions.distinct.pluck(:status)
      assert_nil @package.latest_release_number
      assert_empty @package.versions.where(latest: true)
      assert @package.metadata['packagist_removed_at']
      assert_nil Rails.cache.read(['packagist', 'enrichment', 'psr/log'])
      assert_nil Rails.cache.read(['packagist', 'tagged_versions', 'psr/log'])
      stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
      tagged
      perform(path)
      assert_equal 'active', @package.reload[:status]
      assert_nil @package.metadata['packagist_removed_at']
      assert_nil @version.reload.status
      assert_equal 'removed', absent.reload.status
      assert_equal '1.0.0', @package.latest_release_number
      assert_equal ids, @package.versions.order(:id).pluck(:id)
    end

    test "#{path} preserves stored status and metadata on upstream or schema failure" do
      @package.update!(status: 'abandoned', metadata: {'abandoned' => 'vendor/replacement'})
      original = state
      stub_request(:get, @enrichment_url).to_return(status: 503)
      assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }
      assert_equal original, state
      stub_request(:get, @enrichment_url).to_return(body: 'invalid json')
      assert_raises(JSON::ParserError) { perform(path) }
      assert_equal original, state
      stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
      stub_request(:get, @tagged_url).to_return(status: 404)
      assert_raises(Ecosystem::Packagist::RetryableError) { perform(path) }
      assert_equal original, state
      tagged(abandoned: {'invalid' => true})
      assert_raises(RuntimeError) { perform(path) }
      assert_equal original, state
    end
  end

  test 'empty tagged and development metadata does not imply abandonment' do
    @package.update!(status: 'abandoned', metadata: {'abandoned' => true})
    tagged(versions: [])

    perform('sync')

    assert_equal 'active', @package.reload[:status]
    assert_equal false, @package.metadata['abandoned']
    assert_not_requested(:get, 'https://repo.packagist.org/p2/psr/log~dev.json')
  end

  test 'tagless packages refresh explicit abandonment from package JSON' do
    tagged(versions: [])
    @enrichment['package']['abandoned'] = 'vendor/replacement'
    stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
    perform('sync')
    assert_equal 'abandoned', @package.reload[:status]
    assert_equal 'vendor/replacement', @package.metadata['abandoned']
    assert_requested(:get, @enrichment_url, times: 1)

    @enrichment['package']['abandoned'] = false
    stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
    perform('versions')
    assert_equal 'active', @package.reload[:status]
    assert_equal false, @package.metadata['abandoned']
    assert_requested(:get, @enrichment_url, times: 2)
  end

  test 'normal absence matches capitalized package names and creates no unknown package' do
    @package.update!(name: 'PSR/Log')
    stub_request(:get, @enrichment_url).to_return(status: 404)
    perform('sync')
    assert_equal 'removed', @package.reload[:status]
    stub_request(:get, 'https://packagist.org/packages/vendor/unknown.json').to_return(status: 404)
    assert_no_difference('Package.count') { SyncPackageWorker.new.perform(@registry.id, 'vendor/unknown', true) }
  end

  test 'an in-flight missing response cannot remove a package refreshed by another worker' do
    newer = nil
    stub_request(:get, @enrichment_url).to_return do
      stub_request(:get, @enrichment_url).to_return(body: @enrichment.to_json)
      perform('sync')
      newer = state
      {status: 404}
    end

    assert_raises(Ecosystem::Packagist::RetryableError) { perform('sync') }

    assert_equal newer, state
  end

  test 'an in-flight successful response cannot restore a concurrently removed package' do
    removed = nil
    stub_request(:get, @tagged_url).to_return do
      stub_request(:get, @tagged_url).to_return(status: 404)
      perform('delete')
      removed = state
      response
    end

    assert_raises(Ecosystem::Packagist::RetryableError) { perform('sync') }

    assert_equal removed, state
  end

  test 'an in-flight delete cannot remove a concurrently recovered package' do
    recovered = nil
    stub_request(:get, @tagged_url).to_return do
      tagged
      perform('sync')
      recovered = state
      {status: 404}
    end

    assert_raises(Ecosystem::Packagist::RetryableError) { perform('delete') }

    assert_equal recovered, state
  end

  test 'a delayed delete older than the stored snapshot cannot remove a recovered package' do
    perform('sync')
    previous = state
    stub_request(:get, @tagged_url).to_return(status: 404)

    assert_raises(Ecosystem::Packagist::RetryableError) do
      SyncPackagistChangeWorker.new.perform(@registry.id, {'type' => 'delete', 'package' => 'psr/log', 'time' => @time.to_i - 1})
    end

    assert_equal previous, state
  end

  test 'pre-deletion metadata cannot revive a package on a later normal sync' do
    perform('sync')
    stub_request(:get, @tagged_url).to_return(status: 404)
    perform('delete')
    previous = state
    stub_request(:get, @tagged_url).to_return(response.merge(headers: {'Last-Modified' => (@time - 1).httpdate}))

    assert_raises(Ecosystem::Packagist::RetryableError) { perform('sync') }

    assert_equal previous, state
  end

  def state
    [@package.reload.attributes, @package.versions.order(:id).map(&:attributes)]
  end

  def perform(path)
    case path
    when 'sync' then SyncPackageWorker.new.perform(@registry.id, 'psr/log', true)
    when 'by_id'
      @package.update_column(:last_synced_at, 2.days.ago) if @package.last_synced_at && @package.last_synced_at > 1.day.ago
      SyncPackageByIdWorker.new.perform(@registry.id, @package.id)
    when 'versions' then UpdateVersionsWorker.new.perform(@package.id)
    when 'status' then CheckPackageStatusWorker.new.perform(@registry.id, @package.id)
    else
      type = path == 'changes' ? 'update' : path
      SyncPackagistChangeWorker.new.perform(@registry.id, {'type' => type, 'package' => 'psr/log', 'time' => @time.to_i})
    end
  end

  def tagged(abandoned: false, versions: nil)
    @time += 1.second
    stub_request(:get, @tagged_url).to_return(response(abandoned: abandoned, versions: versions))
  end

  def response(abandoned: false, versions: nil)
    release = {'name' => 'psr/log', 'version' => '1.0.0', 'time' => '2026-11-01T00:00:00Z'}
    release['abandoned'] = abandoned unless abandoned == false
    {body: {packages: {'psr/log' => versions || [release]}}.to_json, headers: {'Last-Modified' => @time.httpdate}}
  end
end
