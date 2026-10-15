require "test_helper"

class MavenCentralPublishedAtWorkerTest < ActiveSupport::TestCase
  setup do
    @strategy = Sidekiq::Throttled::Registry.get(MavenCentralPublishedAtWorker)
    @strategy.reset!
    @registry = Registry.create!(url: 'https://maven-central.storage-download.googleapis.com/maven2', name: 'repo1.maven.org', ecosystem: 'maven')
    package = @registry.packages.create!(name: 'junit:junit', ecosystem: 'maven')
    @version = package.versions.create!(number: '4.12', registry: @registry)
    @head = "https://repo1.maven.org/maven2/junit/junit/4.12/junit-4.12.pom"
  end

  teardown do
    @strategy.reset!
  end

  test 'dates an undated version from Maven Central' do
    stub_request(:head, @head).to_return(status: 200, headers: { 'Last-Modified' => 'Thu, 04 Dec 2014 16:17:43 GMT' })

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_equal Time.utc(2014, 12, 4, 16, 17, 43), @version.reload.read_attribute(:published_at)
  end

  test 'refreshes existing package dates during a backfill' do
    package = @version.package
    package.update!(first_release_published_at: Time.utc(2019, 7, 14), latest_release_published_at: Time.utc(2019, 7, 14))
    stub_request(:head, @head).to_return(status: 200, headers: { 'Last-Modified' => 'Thu, 04 Dec 2014 16:17:43 GMT' })

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_equal Time.utc(2014, 12, 4, 16, 17, 43), package.reload.first_release_published_at
    assert_equal Time.utc(2014, 12, 4, 16, 17, 43), package.latest_release_published_at
  end

  test 'skips a version that already has a date' do
    @version.update_column(:published_at, Time.utc(2014, 12, 4))

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_not_requested :head, @head
  end

  [429, 503].each do |status|
    test "retries a Central #{status} response and saves the date on success" do
      stub_request(:head, @head).to_return(status: status).then
        .to_return(status: 200, headers: { 'Last-Modified' => 'Thu, 04 Dec 2014 16:17:43 GMT' })

      assert_raises(Faraday::Error) do
        MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')
      end
      assert_nil @version.reload.read_attribute(:published_at)

      MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

      assert_equal Time.utc(2014, 12, 4, 16, 17, 43), @version.reload.read_attribute(:published_at)
      assert_requested :head, @head, times: 2
    end
  end

  test 'retries a Central timeout and saves the date on success' do
    stub_request(:head, @head).to_timeout.then
      .to_return(status: 200, headers: { 'Last-Modified' => 'Thu, 04 Dec 2014 16:17:43 GMT' })

    assert_raises(Faraday::TimeoutError) do
      MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')
    end
    assert_nil @version.reload.read_attribute(:published_at)

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_equal Time.utc(2014, 12, 4, 16, 17, 43), @version.reload.read_attribute(:published_at)
    assert_requested :head, @head, times: 2
  end

  test 'leaves the version undated when Central has no artifact' do
    stub_request(:head, @head).to_return(status: 404)

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_nil @version.reload.read_attribute(:published_at)
  end

  test 'limits Maven Central lookups to two a second across all jobs' do
    2.times { refute @strategy.throttled?(SecureRandom.hex, @registry.id, 'junit:junit', '4.12') }

    assert @strategy.throttled?(SecureRandom.hex, @registry.id, 'junit:junit', '4.13')
  end
end
