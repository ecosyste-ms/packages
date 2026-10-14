require "test_helper"

class SyncPackageWorkerTest < ActiveSupport::TestCase
  {
    'GitHub' => 'https://github.com/github-community-projects/graphql-client',
    'GitLab' => 'https://gitlab.com/gitlab-community-projects/subgroup/graphql-client',
    'Bitbucket' => 'https://bitbucket.org/bitbucket-org/graphql-client'
  }.each do |host, repository_url|
    test "sync preserves the #{host} repository URL from RubyGems metadata" do
      registry = Registry.create!(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
      stub_request(:get, 'https://rubygems.org/api/v1/gems/graphql-client.json')
        .to_return(status: 200, body: {
          name: 'graphql-client', homepage_uri: repository_url, source_code_uri: nil, licenses: ['MIT']
        }.to_json)
      stub_request(:get, 'https://rubygems.org/api/v1/versions/graphql-client.json')
        .to_return(status: 200, body: '[]')

      SyncPackageWorker.new.perform(registry.id, 'graphql-client')

      package = registry.packages.find_by!(name: 'graphql-client')
      assert_equal repository_url, package.repository_url
    end
  end

  {
    'github_commenter' => {
      homepage: 'https://github.com/okitan/github_commenter',
      documentation: 'https://rubydoc.info/gems/github_commenter',
      stored: 'https://github.com/rubydoc.info/gems',
      expected: 'https://github.com/okitan/github_commenter'
    },
    'duplicate-homepage' => {
      homepage: 'https://github.com/https://github.com/isovector/type-sets/tree/master/magic-tyfams#readme',
      stored: 'https://github.com/github.com/isovector',
      expected: 'https://github.com/isovector/type-sets'
    }
  }.each do |name, urls|
    test "forced sync repairs the repository URL for #{name}" do
      registry = Registry.create!(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
      package = registry.packages.create!(name: name, ecosystem: 'rubygems', repository_url: urls[:stored], last_synced_at: Time.current)
      stub_request(:get, "https://rubygems.org/api/v1/gems/#{name}.json")
        .to_return(status: 200, body: {
          name: name, homepage_uri: urls[:homepage], documentation_uri: urls[:documentation], licenses: ['MIT']
        }.to_json)
      stub_request(:get, "https://rubygems.org/api/v1/versions/#{name}.json")
        .to_return(status: 200, body: '[]')
      UpdateRepoMetadataWorker.expects(:perform_async).with(package.id)

      SyncPackageWorker.new.perform(registry.id, name, true)

      assert_equal urls[:expected], package.reload.repository_url
    end
  end

  test 'forced CPAN sync preserves the repository URL with repeated hosts in metadata' do
    registry = Registry.create!(name: 'cpan.org', url: 'https://cpan.org', ecosystem: 'cpan')
    name = 'DBIx-Class-FilterColumn-ByType'
    expected = "https://github.com/mattp-/#{name}"
    package = registry.packages.create!(name: name, ecosystem: 'cpan', repository_url: expected, last_synced_at: Time.current)
    stub_request(:get, "https://fastapi.metacpan.org/v1/release/#{name}")
      .to_return(status: 200, body: {
        distribution: name,
        resources: {
          repository: { url: "git://github.com///github.com/mattp-/#{name}.git" },
          homepage: "https://github.com///github.com/mattp-/#{name}/wiki",
          bugtracker: { web: "https://github.com///github.com/mattp-/#{name}/issues" }
        }
      }.to_json)
    stub_request(:get, 'https://fastapi.metacpan.org/v1/release/_search')
      .with(query: { q: "distribution:#{name}", size: '5000' })
      .to_return(status: 200, body: { hits: { hits: [] } }.to_json)

    SyncPackageWorker.new.perform(registry.id, name, true)

    assert_equal expected, package.reload.repository_url
  end

  test 'perform' do
    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @registry.expects(:sync_package).with('foo', force: false)
    Registry.expects(:find_by_id).with(@registry.id).returns(@registry)
    job = SyncPackageWorker.new
    job.perform(@registry.id, 'foo')
  end

  test 'perform force sync' do
    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @registry.expects(:sync_package).with('foo', force: true)
    Registry.expects(:find_by_id).with(@registry.id).returns(@registry)

    SyncPackageWorker.new.perform(@registry.id, 'foo', true)
  end
end
