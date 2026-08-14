require "test_helper"

class UpdateDownloadCountsWorkerTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    @a = @registry.packages.create!(name: 'aaa', ecosystem: 'npm')
    @b = @registry.packages.create!(name: 'bbb', ecosystem: 'npm', downloads_updated_at: 1.day.ago)
    @removed = @registry.packages.create!(name: 'gone', ecosystem: 'npm', status: 'removed')
  end

  test "perform delegates to Registry#update_download_counts" do
    Registry.any_instance.expects(:update_download_counts)
    UpdateDownloadCountsWorker.new.perform(@registry.id)
  end

  test "shares the registry_host throttle strategy" do
    assert_same Sidekiq::Throttled::Registry.get(:registry_host),
                Sidekiq::Throttled::Registry.get('UpdateDownloadCountsWorker')
  end

  test "update_download_counts walks by name, stamps timestamps and skips removed" do
    @registry.ecosystem_instance.expects(:fetch_download_counts).with(['aaa', 'bbb']).returns('aaa' => 42)
    processed = @registry.update_download_counts(limit: 10)
    assert_equal 2, processed
    assert_equal 42, @a.reload.downloads
    assert_not_nil @a.downloads_updated_at
    assert_nil @b.reload.downloads
    assert @b.downloads_updated_at > 1.hour.ago
    assert_nil @removed.reload.downloads_updated_at
    assert_equal 'bbb', @registry.reload.metadata['download_counts_cursor']
  end

  test "update_download_counts advances cursor and wraps at end" do
    @registry.ecosystem_instance.expects(:fetch_download_counts).with(['aaa']).returns({})
    @registry.update_download_counts(limit: 1)
    assert_equal 'aaa', @registry.reload.metadata['download_counts_cursor']

    @registry.ecosystem_instance.expects(:fetch_download_counts).with(['bbb']).returns({})
    @registry.update_download_counts(limit: 1)
    assert_equal 'bbb', @registry.reload.metadata['download_counts_cursor']

    assert_equal 0, @registry.update_download_counts(limit: 1)
    assert_equal '', @registry.reload.metadata['download_counts_cursor']
  end

  test "update_download_counts writes a zero count" do
    @a.update_column(:downloads, 999)
    @registry.ecosystem_instance.expects(:fetch_download_counts).with(['aaa', 'bbb']).returns('aaa' => 0)
    @registry.update_download_counts(limit: 10)
    assert_equal 0, @a.reload.downloads
  end

  test "top mode picks highest-download packages and does not touch the cursor" do
    @a.update_column(:downloads, 100)
    @b.update_column(:downloads, 50)
    @registry.ecosystem_instance.expects(:fetch_download_counts).with(['aaa', 'bbb']).returns('aaa' => 110, 'bbb' => 55)
    @registry.update_download_counts(limit: 10, top: true)
    assert_equal 110, @a.reload.downloads
    assert_equal 55, @b.reload.downloads
    assert_nil @registry.reload.metadata['download_counts_cursor']
  end

  test "cursor write goes through merge_metadata_key" do
    @registry.expects(:merge_metadata_key).with('download_counts_cursor', 'bbb')
    @registry.ecosystem_instance.expects(:fetch_download_counts).with(['aaa', 'bbb']).returns({})
    @registry.update_download_counts(limit: 10)
  end

  test "update_download_counts is a no-op when ecosystem has no fetch_download_counts" do
    r = Registry.create!(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    r.packages.create!(name: 'x', ecosystem: 'cargo')
    assert_equal 0, r.update_download_counts
  end
end
