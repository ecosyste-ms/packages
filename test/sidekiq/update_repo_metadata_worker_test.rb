require "test_helper"

class UpdateRepoMetadataWorkerTest < ActiveSupport::TestCase
  setup do
    @strategy = Sidekiq::Throttled::Registry.get(UpdateRepoMetadataWorker)
    @strategy.reset!
  end

  teardown do
    @strategy.reset!
  end

  test "runs on its own queue" do
    assert_equal "repo_metadata", UpdateRepoMetadataWorker.get_sidekiq_options["queue"].to_s
  end

  test "completes a metadata update when the fallback homepage query is not UTF-8" do
    registry = Registry.create!(name: 'pkgsrc.se', url: 'https://pkgsrc.se', ecosystem: 'pkgsrc')
    homepage = 'http://openlab.ring.gr.jp/skk/wiki/wiki.cgi?page=SKK%BC%AD%BD%F1'
    previous_update = 2.days.ago
    metadata = { 'full_name' => 'existing/repository' }
    package = registry.packages.create!(name: 'inputmethod/skk-jisyo', ecosystem: 'pkgsrc',
      homepage: homepage, repo_metadata: metadata, repo_metadata_updated_at: previous_update)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup')
      .with(query: { url: homepage }).to_return(status: 404)

    UpdateRepoMetadataWorker.new.perform(package.id)

    assert_operator package.reload.repo_metadata_updated_at, :>, previous_update
    assert_equal metadata, package.repo_metadata
    assert_equal homepage, package.homepage
    assert_requested :get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup', query: { url: homepage }, times: 1
  end

  test "follows a fallback redirect with a UTF-8 query" do
    registry = Registry.create!(name: 'pkgsrc.se', url: 'https://pkgsrc.se', ecosystem: 'pkgsrc')
    homepage = 'https://example.org/project?q=%C3%A9'
    redirected_url = 'https://example.org/renamed'
    previous_update = 2.days.ago
    package = registry.packages.create!(name: 'inputmethod/example', ecosystem: 'pkgsrc',
      homepage: homepage, repo_metadata_updated_at: previous_update)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup')
      .with(query: { url: homepage }).to_return(status: 404)
    stub_request(:head, homepage).to_return(status: 302, headers: { 'Location' => redirected_url })
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup')
      .with(query: { url: redirected_url }).to_return(status: 404)

    UpdateRepoMetadataWorker.new.perform(package.id)

    assert_operator package.reload.repo_metadata_updated_at, :>, previous_update
    assert_requested :head, homepage, times: 1
    assert_requested :get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup', query: { url: redirected_url }, times: 1
  end

  test "raises unrelated argument errors in the fallback request" do
    registry = Registry.create!(name: 'pkgsrc.se', url: 'https://pkgsrc.se', ecosystem: 'pkgsrc')
    homepage = 'https://example.org/project'
    previous_update = 2.days.ago
    package = registry.packages.create!(name: 'inputmethod/example', ecosystem: 'pkgsrc',
      homepage: homepage, repo_metadata_updated_at: previous_update)
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup')
      .with(query: { url: homepage }).to_return(status: 404)
    stub_request(:head, homepage).to_raise(ArgumentError.new('unexpected argument'))

    error = assert_raises(ArgumentError) { UpdateRepoMetadataWorker.new.perform(package.id) }

    assert_equal 'unexpected argument', error.message
    assert_in_delta previous_update, package.reload.repo_metadata_updated_at, 1.second
  end

  test "limits concurrent repository metadata updates" do
    jids = 25.times.map { SecureRandom.hex }

    jids.each do |jid|
      refute @strategy.throttled?(jid, 1)
    end
    assert @strategy.throttled?(SecureRandom.hex, 1)

    @strategy.finalize!(jids.first, 1)
    refute @strategy.throttled?(SecureRandom.hex, 1)
  end

  test "requeues the existing unique job when throttled" do
    assert_equal :enqueue, @strategy.requeue_with
  end
end
