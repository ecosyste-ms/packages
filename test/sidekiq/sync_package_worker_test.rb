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
