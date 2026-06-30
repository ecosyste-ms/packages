require "test_helper"

class TopDependentPackageTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:package)
  end

  test 'cacheable_request? matches sort and direction' do
    assert TopDependentPackage.cacheable_request?(sort: 'downloads')
    assert TopDependentPackage.cacheable_request?(sort: 'downloads', order: 'desc')
    assert TopDependentPackage.cacheable_request?(sort: 'rank', order: 'asc')
    assert TopDependentPackage.cacheable_request?(sort: 'dependent_packages_count')
    assert TopDependentPackage.cacheable_request?(sort: 'dependent_repos_count')
  end

  test 'cacheable_request? rejects wrong direction' do
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', order: 'asc')
    refute TopDependentPackage.cacheable_request?(sort: 'rank')
    refute TopDependentPackage.cacheable_request?(sort: 'rank', order: 'desc')
  end

  test 'cacheable_request? rejects unknown sort' do
    refute TopDependentPackage.cacheable_request?(sort: 'name')
    refute TopDependentPackage.cacheable_request?(sort: nil)
    refute TopDependentPackage.cacheable_request?({})
  end

  test 'cacheable_request? rejects filters' do
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', latest: 'false')
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', kind: 'runtime')
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', min_stars: '10')
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', min_downloads: '100')
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', created_after: '2025-01-01')
    refute TopDependentPackage.cacheable_request?(sort: 'downloads', updated_after: '2025-01-01')
  end
end
