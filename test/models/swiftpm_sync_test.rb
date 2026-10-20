require "test_helper"

class SwiftpmSyncTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(default: true, name: 'Swiftpm.io', url: 'https://swiftpm.io', ecosystem: 'swiftpm')
    @name = 'github.com/swift-cloud/Compute'
    @lookup = JSON.parse(file_fixture('swiftpm/lookup?url=https:%2F%2Fgithub.com%2Fswift-cloud%2FCompute').read)
    Package.any_instance.stubs(:update_repo_metadata_async)
    Package.any_instance.stubs(:update_dependent_repos_count_async)
    stub_request(:get, %r{\Ahttps://raw.githubusercontent.com/swift-cloud/Compute/.+/Package.resolved\z})
      .to_return(status: 404)
  end

  def sync(tags: [], status: 200)
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://#{@name}")
      .to_return(status: 200, body: @lookup.to_json)
    stub_request(:get, "#{@lookup['tags_url']}?per_page=1000")
      .to_return(status: status, body: tags.to_json)
    SyncPackageWorker.new.perform(@registry.id, @name, true)
    @registry.packages.find_by_normalized_name!(@name, normalized_name: Ecosystem::Swiftpm.normalized_package_name(@name)).reload
  end

  def tags(*names)
    names.map do |name|
      {name: name, sha: 'abc123', published_at: '2022-11-26T23:40:38Z',
       download_url: "https://codeload.github.com/swift-cloud/Compute/tar.gz/#{name}"}
    end
  end

  test 'sync persists the default branch and uses it for unversioned downloads' do
    package = sync
    assert_equal 'main', package.metadata['default_branch']
    assert_equal 'github.com/swift-cloud/compute', package.metadata['normalized_name']
    assert_equal 'swift-cloud.Compute', package.metadata['tuist_registry_identity']
    assert_equal 'https://codeload.github.com/swift-cloud/Compute/tar.gz/refs/heads/main', package.download_url

    @lookup['default_branch'] = 'release/next'
    assert_equal 'https://codeload.github.com/swift-cloud/Compute/tar.gz/refs/heads/release%2Fnext', sync.download_url
  end

  test 'download uses existing repository metadata when lookup has no default branch' do
    @lookup.delete('default_branch')
    package = sync
    assert_nil package.download_url
    package.update!(repo_metadata: {'default_branch' => 'develop'})
    assert_equal 'https://codeload.github.com/swift-cloud/Compute/tar.gz/refs/heads/develop', package.download_url
  end

  test 'versioned downloads retain the tag archive' do
    package = sync(tags: tags('1.11.0'))
    assert_equal 'https://codeload.github.com/swift-cloud/Compute/tar.gz/1.11.0', package.download_url
  end

  test 'sync stores Tuist identities with dots converted to underscores' do
    @name = 'github.com/groue/GRDB.swift'
    @lookup.merge!('full_name' => 'groue/GRDB.swift', 'owner' => 'groue')
    assert_equal 'groue.GRDB_swift', sync.metadata['tuist_registry_identity']
  end

  test 'sync reuses the canonical package across casing variants without replacing its versions' do
    package = sync(tags: tags('1.0.0'))
    version_id = package.versions.first.id
    @name = @name.upcase
    synced = sync(tags: tags('1.0.0'))
    assert_equal package.id, synced.id
    assert_equal version_id, synced.versions.first.id
    assert_equal 'github.com/swift-cloud/Compute', synced.name
    assert_equal 1, @registry.packages.count
  end

  test 'sync refuses an ambiguous canonical identity without creating another package' do
    package = sync(tags: tags('1.0.0'))
    duplicate = @registry.packages.create!(name: 'github.com/SWIFT-CLOUD/Compute', ecosystem: 'swiftpm', metadata: package.metadata)
    @name = @name.upcase
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://#{@name}")
      .to_return(status: 200, body: @lookup.to_json)

    SyncPackageWorker.new.perform(@registry.id, @name, true)

    assert_equal 2, @registry.packages.count
    assert_equal ['1.0.0'], package.versions.pluck(:number)
    assert_nil duplicate.reload.last_synced_at
    assert_requested(:get, "#{@lookup['tags_url']}?per_page=1000", times: 1)
  end

  test 'non GitHub repositories have no Tuist identity or GitHub fallback download' do
    @name = 'gitlab.com/example/Library'
    assert_nil sync.metadata['tuist_registry_identity']
    assert_nil sync.download_url

    @name = 'github.com.example.org/example/Library'
    package = sync
    assert_nil package.metadata['tuist_registry_identity']
    assert_nil package.download_url
    assert_equal 'https://github.com.example.org/example/Library', package.registry_url
    assert_nil package.documentation_url
  end

  test 'sync reads dependencies from supported non GitHub hosts' do
    repositories = {
      'gitlab.com/example/group/Library' => 'https://gitlab.com/api/v4/projects/example%2Fgroup%2FLibrary/repository/files/Package.resolved/raw?ref=1.0.0',
      'bitbucket.org/example/Library' => 'https://api.bitbucket.org/2.0/repositories/example/Library/src/1.0.0/Package.resolved',
      'codeberg.org/example/Library' => 'https://codeberg.org/api/v1/repos/example/Library/raw/Package.resolved?ref=1.0.0'
    }
    repositories.each do |name, url|
      @name = name
      stub_request(:get, url).to_return(status: 200, body: file_fixture('swiftpm/Package.resolved'))
      package = sync(tags: tags('1.0.0'))
      assert_equal 2, package.versions.first.dependencies.count, name
      assert_nil package.metadata['tuist_registry_identity'], name
      assert_requested(:get, url)
    end
  end

  test 'sync does not read dependencies from unsupported hosts' do
    @name = 'git.example.org/example/Library'
    package = sync(tags: tags('1.0.0'))
    assert_empty package.versions.first.dependencies
  end

  test 'failed dependency responses are not parsed even when they contain valid JSON' do
    stub_request(:get, 'https://raw.githubusercontent.com/swift-cloud/Compute/1.0.0/Package.resolved')
      .to_return(status: 500, body: file_fixture('swiftpm/Package.resolved'))
    assert_empty sync(tags: tags('1.0.0')).versions.first.dependencies
  end

  test 'sync links existing GitHub case variants and refreshes dependent counts' do
    target = @registry.packages.create!(name: 'github.com/Krzyzanowskim/cryptoswift', ecosystem: 'swiftpm', metadata: {'normalized_name' => 'github.com/krzyzanowskim/cryptoswift'})
    stub_request(:get, 'https://raw.githubusercontent.com/swift-cloud/Compute/1.0.0/Package.resolved')
      .to_return(status: 200, body: file_fixture('swiftpm/Package.resolved'))
    package = sync(tags: tags('1.0.0'))
    dependency = package.versions.first.dependencies.find_by!(package_name: 'github.com/krzyzanowskim/cryptoswift')
    assert_equal target.id, dependency.package_id
    assert_equal 1, target.reload.dependent_packages_count
  end

  test 'sync links old dependency rows without a new version' do
    stub_request(:get, 'https://raw.githubusercontent.com/swift-cloud/Compute/1.0.0/Package.resolved')
      .to_return(status: 200, body: file_fixture('swiftpm/Package.resolved'))
    package = sync(tags: tags('1.0.0'))
    target = @registry.packages.create!(name: 'github.com/Krzyzanowskim/cryptoswift', ecosystem: 'swiftpm', metadata: {'normalized_name' => 'github.com/krzyzanowskim/cryptoswift'})
    sync(tags: tags('1.0.0'))
    assert_equal target.id, package.versions.first.dependencies.find_by!(package_name: 'github.com/krzyzanowskim/cryptoswift').package_id
    assert_equal 1, target.reload.dependent_packages_count
    assert_requested(:get, 'https://raw.githubusercontent.com/swift-cloud/Compute/1.0.0/Package.resolved', times: 1)
  end

  test 'sync of a dependency target links previously imported case variants' do
    consumer = @registry.packages.create!(name: 'github.com/example/App', ecosystem: 'swiftpm')
    version = consumer.versions.create!(number: '1.0.0')
    dependency = version.dependencies.create!(package_name: @name.downcase, ecosystem: 'swiftpm', requirements: '*', kind: 'runtime')
    package = sync
    assert_equal package.id, dependency.reload.package_id
    assert_equal 1, package.reload.dependent_packages_count
  end

  test 'sync accepts Swift version tags and rejects arbitrary labels' do
    accepted = %w[1.2.3 v2.0.0 3.0.0-beta.1 3.0.0+build.1 1.2 1.2.3@swift-6 1.2.3@swift-6.1 1.2.3@swift-6.1.2]
    rejected = %w[nightly release-candidate release-1.2.3 1 1.2.3.4 V1.2.3 1.2.3@swift-nope]
    package = sync(tags: tags(*(accepted + rejected)))
    assert_equal accepted.sort, package.versions.pluck(:number).sort
  end

  test 'filtering a full tag page does not remove older versions' do
    package = sync(tags: tags('1.0.0'))
    page = tags('2.0.0') + (1...1000).map { |i| {name: "nightly-#{i}"} }
    sync(tags: page)
    assert_nil package.versions.find_by!(number: '1.0.0').status
    assert_equal 2, package.versions.count
  end

  test 'complete filtered responses remove invalid and missing versions' do
    package = sync(tags: tags('1.0.0'))
    package.versions.create!(number: 'nightly')
    sync(tags: tags('nightly', '2.0.0'))
    assert_equal %w[1.0.0 nightly], package.versions.where(status: 'removed').order(:number).pluck(:number)
    assert_equal ['2.0.0'], package.versions.active.pluck(:number)
    sync(tags: tags('1.0.0'))
    assert_nil package.versions.find_by!(number: '1.0.0').status
  end

  test 'failed and malformed tag responses preserve versions' do
    package = sync(tags: tags('1.0.0'))
    sync(tags: {error: 'rate limited'}, status: 429)
    sync(tags: [], status: 500)
    sync(tags: [{name: nil}])
    assert_nil package.versions.find_by!(number: '1.0.0').status
  end

  test 'successful empty tag responses remove old versions' do
    package = sync(tags: tags('1.0.0'))
    sync
    assert_equal 'removed', package.versions.find_by!(number: '1.0.0').status
  end
end
