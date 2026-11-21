require "test_helper"

class SyncPackageWorkerTest < ActiveSupport::TestCase
  {
    'empty error response' => { status: 402, body: '' },
    'null response' => { status: 200, body: 'null' },
    'missing distribution' => { status: 404, body: '{"message":"Not found","code":404}' }
  }.each do |description, response|
    test "CPAN sync returns false for #{description}" do
      registry = Registry.create!(name: 'cpan.org', url: 'https://cpan.org', ecosystem: 'cpan')
      name = 'JavaScript::Minifier::XS'
      url = "https://fastapi.metacpan.org/v1/release/#{name}"
      stub_request(:get, url).to_return(response)

      assert_equal false, SyncPackageWorker.new.perform(registry.id, name)

      assert_empty registry.packages
      assert_requested :get, url, times: 1
    end
  end

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

  test 'sync persists the latest published release number for an all-deprecated package' do
    registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go')
    module_path = 'github.com/example/all-deprecated'
    stub_request(:get, "https://pkg.go.dev/v1beta/module/#{module_path}?licenses=true")
      .to_return(body: { path: module_path, version: 'v2.0.0', repoUrl: 'https://github.com/example/all-deprecated', licenses: [{ types: ['MIT'] }] }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/package/#{module_path}")
      .to_return(body: { modulePath: module_path, version: 'v2.0.0', path: module_path, synopsis: 'Deprecated module' }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/#{module_path}?limit=1000")
      .to_return(body: { items: [
        { modulePath: module_path, version: 'v2.0.0', commitTime: '2025-01-01T00:00:00Z', retracted: false, deprecated: true },
        { modulePath: module_path, version: 'v1.0.0', commitTime: '2024-01-01T00:00:00Z', retracted: false, deprecated: true }
      ] }.to_json)
    %w[v1.0.0 v2.0.0].each do |version|
      stub_request(:get, "https://proxy.golang.org/cached-only/#{module_path}/@v/#{version}.mod")
        .to_return(body: "module #{module_path}\n\ngo 1.24\n")
    end

    SyncPackageWorker.new.perform(registry.id, module_path, true)

    package = registry.packages.find_by!(name: module_path)
    assert_nil package.reload.latest_release_number
    assert_equal 'v2.0.0', package.latest_published_release_number
  end

  test 'sync persists both release numbers for a mixed package whose highest version is deprecated' do
    registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go')
    module_path = 'github.com/example/mixed'
    stub_request(:get, "https://pkg.go.dev/v1beta/module/#{module_path}?licenses=true")
      .to_return(body: { path: module_path, version: 'v2.0.0', repoUrl: 'https://github.com/example/mixed', licenses: [{ types: ['MIT'] }] }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/package/#{module_path}")
      .to_return(body: { modulePath: module_path, version: 'v2.0.0', path: module_path, synopsis: 'Mixed module' }.to_json)
    stub_request(:get, "https://pkg.go.dev/v1beta/versions/#{module_path}?limit=1000")
      .to_return(body: { items: [
        { modulePath: module_path, version: 'v2.0.0', commitTime: '2025-01-01T00:00:00Z', retracted: false, deprecated: true },
        { modulePath: module_path, version: 'v1.0.0', commitTime: '2024-01-01T00:00:00Z', retracted: false, deprecated: false }
      ] }.to_json)
    %w[v1.0.0 v2.0.0].each do |version|
      stub_request(:get, "https://proxy.golang.org/cached-only/#{module_path}/@v/#{version}.mod")
        .to_return(body: "module #{module_path}\n\ngo 1.24\n")
    end

    SyncPackageWorker.new.perform(registry.id, module_path, true)

    package = registry.packages.find_by!(name: module_path)
    assert_equal 'v1.0.0', package.reload.latest_release_number
    assert_equal 'v2.0.0', package.latest_published_release_number
  end

  test 'perform force sync' do
    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @registry.expects(:sync_package).with('foo', force: true)
    Registry.expects(:find_by_id).with(@registry.id).returns(@registry)

    SyncPackageWorker.new.perform(@registry.id, 'foo', true)
  end
end
