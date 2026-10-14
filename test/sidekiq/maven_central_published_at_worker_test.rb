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

  test 'skips a version that already has a date' do
    @version.update_column(:published_at, Time.utc(2014, 12, 4))

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_not_requested :head, @head
  end

  test 'leaves the version undated when Central does not answer' do
    stub_request(:head, @head).to_return(status: 429)

    MavenCentralPublishedAtWorker.new.perform(@registry.id, 'junit:junit', '4.12')

    assert_nil @version.reload.read_attribute(:published_at)
  end

  test 'limits Maven Central lookups to two a second across all jobs' do
    2.times { refute @strategy.throttled?(SecureRandom.hex, @registry.id, 'junit:junit', '4.12') }

    assert @strategy.throttled?(SecureRandom.hex, @registry.id, 'junit:junit', '4.13')
  end
end
