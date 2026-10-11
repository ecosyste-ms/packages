require 'test_helper'

class RegistryRankingsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(name: 'rankings.example', url: 'https://rankings.example', ecosystem: 'huggingface')
  end

  def create_package(name, status: 'active', **attributes)
    @registry.packages.create!(name: name, ecosystem: @registry.ecosystem, status: status, **attributes)
  end

  def expected_rankings(packages)
    @registry.reload
    packages.to_h { |package| [package.id, package.reload.load_rankings.deep_stringify_keys] }
  end

  def stored_rankings(packages)
    packages.to_h { |package| [package.id, package.reload.rankings] }
  end

  test 'matches load_rankings across ties, gaps, statuses and repository counts' do
    packages = [
      create_package('org/leader', downloads: 500, dependent_packages_count: 9, dependent_repos_count: 30, docker_downloads_count: 7,
                                   repo_metadata: { 'stargazers_count' => 120, 'forks_count' => 15 }),
      create_package('org/tied-a', downloads: 100, dependent_packages_count: 2, dependent_repos_count: 4,
                                   repo_metadata: { 'stargazers_count' => 40, 'forks_count' => 0 }),
      create_package('org/tied-b', downloads: 100, dependent_packages_count: 2, dependent_repos_count: 0,
                                   repo_metadata: { 'stargazers_count' => '40' }),
      create_package('org/zero', downloads: 0, dependent_packages_count: 0, dependent_repos_count: 0),
      create_package('org/no-downloads', downloads: nil, dependent_packages_count: 1, dependent_repos_count: 1, repo_metadata: {}),
      create_package('org/removed-high', status: 'removed', downloads: 10_000, dependent_packages_count: 50, dependent_repos_count: 99,
                                         repo_metadata: { 'stargazers_count' => 999 }),
      create_package('org/removed-low', status: 'removed', downloads: 1),
    ]
    expected = expected_rankings(packages)

    assert_equal packages.length, @registry.update_rankings

    assert_equal expected, stored_rankings(packages)
  end

  test 'matches load_rankings on a larger set with many ties' do
    random = Random.new(1888)
    packages = 60.times.map do |i|
      metadata = random.rand < 0.3 ? {} : { 'stargazers_count' => random.rand(0..5), 'forks_count' => random.rand(0..3) }
      create_package("org/pkg-#{i}", status: random.rand < 0.2 ? 'removed' : 'active',
                                     downloads: random.rand < 0.2 ? nil : random.rand(0..8),
                                     dependent_packages_count: random.rand(0..4), dependent_repos_count: random.rand(0..4),
                                     docker_downloads_count: random.rand < 0.5 ? nil : random.rand(0..2), repo_metadata: metadata)
    end
    expected = expected_rankings(packages)

    @registry.update_rankings(batch_size: 7)

    assert_equal expected, stored_rankings(packages)
  end

  test 'divides by every package in the registry while counting only active packages above' do
    top = create_package('org/top', downloads: 50)
    low = create_package('org/low', downloads: 10)
    create_package('org/gone', status: 'removed', downloads: 90)
    create_package('org/gone-2', status: 'removed', downloads: 5)

    @registry.reload.update_rankings

    assert_equal 0.0, top.reload.rankings['downloads']
    assert_equal 25.0, low.reload.rankings['downloads']
  end

  test 'skips fields every package ties at zero and falls back to the bottom average' do
    packages = 2.times.map { |i| create_package("org/zero-#{i}", downloads: 0) }

    @registry.reload.update_rankings

    packages.each do |package|
      assert_equal 0.0, package.reload.rankings['downloads']
      assert_equal 100, package.rankings['average']
    end
  end

  test 'keeps other ranking keys such as underproduction' do
    underproduction = { 'usage_rank' => 1, 'quality_rank' => 2, 'production' => -0.3 }
    package = create_package('org/model', downloads: 10, rankings: { 'underproduction' => underproduction })

    @registry.reload.update_rankings

    assert_equal underproduction, package.reload.rankings['underproduction']
    assert_equal 0.0, package.rankings['average']
  end

  test 'leaves unchanged rankings untouched on a second pass' do
    packages = [create_package('org/a', downloads: 10), create_package('org/b', downloads: 20)]
    @registry.reload.update_rankings
    updated_at = packages.map { |package| package.reload.updated_at }

    assert_equal 0, @registry.update_rankings
    assert_equal updated_at, packages.map { |package| package.reload.updated_at }
  end

  test 'refreshes rankings that were stale from an earlier registry size' do
    first = create_package('org/first', downloads: 1)
    first.reload.update_rankings
    assert_equal 0.0, first.reload.rankings['average']

    3.times { |i| create_package("org/later-#{i}", downloads: 10 + i) }
    @registry.reload.update_rankings

    assert_equal 75.0, first.reload.rankings['downloads']
    assert_equal 75.0, first.rankings['average']
  end

  test 'pages through packages in batches' do
    packages = 5.times.map { |i| create_package("org/batch-#{i}", downloads: i) }
    expected = expected_rankings(packages)

    assert_equal 5, @registry.update_rankings(batch_size: 2)

    assert_equal expected, stored_rankings(packages)
  end

  test 'only ranks packages from its own registry' do
    other = Registry.create!(name: 'other.example', url: 'https://other.example', ecosystem: 'huggingface')
    outsider = other.packages.create!(name: 'org/outsider', ecosystem: 'huggingface', downloads: 1_000)
    package = create_package('org/insider', downloads: 1)

    @registry.reload.update_rankings

    assert_equal 0.0, package.reload.rankings['downloads']
    assert_equal({}, outsider.reload.rankings)
  end

  test 'does nothing for an empty registry' do
    assert_equal 0, @registry.update_rankings
  end

  test 'update_rankings_async enqueues the registry worker' do
    assert_difference -> { UpdateRegistryRankingsWorker.jobs.size }, 1 do
      @registry.update_rankings_async
    end
    assert_equal [@registry.id], UpdateRegistryRankingsWorker.jobs.last['args']
  end
end
