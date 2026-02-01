require "test_helper"

class RegistryTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:packages)
    should have_many(:versions)
  end

  context 'validations' do
    should validate_presence_of(:url)
    should validate_presence_of(:name)
    should validate_presence_of(:ecosystem)
    should validate_uniqueness_of(:name)
    should validate_uniqueness_of(:url)
  end

  setup do
    @registry = Registry.create(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
  end

  test 'all_package_names' do
    ecosystem = @registry.ecosystem_instance
    ecosystem.expects(:all_package_names).returns(['rails', 'split', 'mocha'])
    all_package_names = @registry.all_package_names
    assert_equal all_package_names, ['rails', 'split', 'mocha']
  end

  test 'recently_updated_package_names' do
    ecosystem = @registry.ecosystem_instance
    ecosystem.expects(:recently_updated_package_names).returns(['oj', 'rake', 'json'])
    recently_updated_package_names = @registry.recently_updated_package_names
    assert_equal recently_updated_package_names, ['oj', 'rake', 'json']
  end

  test 'missing_package_names' do
    @registry.expects(:all_package_names).returns(['foo', 'bar', 'baz'])
    @registry.expects(:existing_package_names).returns(['foo'])
    assert_equal @registry.missing_package_names, ['bar', 'baz']
  end

  test 'missing_package_names handles Hash from all_package_names' do
    # This can happen when an ecosystem's API returns unexpected data
    @registry.expects(:all_package_names).returns({'foo' => 'data', 'bar' => 'data', 'baz' => 'data'})
    @registry.expects(:existing_package_names).returns(['foo'])
    assert_equal @registry.missing_package_names.sort, ['bar', 'baz']
  end

  test 'missing_package_names handles nil from all_package_names' do
    @registry.expects(:all_package_names).returns(nil)
    @registry.expects(:existing_package_names).returns(['foo'])
    assert_equal @registry.missing_package_names, []
  end

  test 'existing_package_names' do
    @registry.save
    @registry.packages.create(name: 'foo', ecosystem: @registry.ecosystem)
    assert_equal @registry.existing_package_names, ['foo']
  end

  test 'sync_all_packages' do
    @registry.expects(:all_package_names).returns(['foo', 'bar', 'baz'])
    @registry.expects(:sync_packages).with(['foo', 'bar', 'baz'])
    @registry.sync_all_packages
  end
  
  test 'sync_missing_packages' do
    @registry.expects(:missing_package_names).returns(['foo', 'bar', 'baz'])
    @registry.expects(:sync_packages).with(['foo', 'bar', 'baz'])
    @registry.sync_missing_packages
  end
  
  test 'sync_recently_updated_packages' do
    @registry.expects(:recently_updated_package_names_excluding_recently_synced).returns(['foo', 'bar', 'baz'])
    @registry.expects(:sync_packages).with(['foo', 'bar', 'baz'])
    @registry.sync_recently_updated_packages
  end

  test 'sync_all_packages_async' do
    @registry.expects(:all_package_names).returns(['foo', 'bar', 'baz'])
    @registry.expects(:sync_packages_async).with(['foo', 'bar', 'baz'])
    @registry.sync_all_packages_async
  end
  
  test 'sync_missing_packages_async' do
    @registry.expects(:missing_package_names).returns(['foo', 'bar', 'baz'])
    @registry.expects(:sync_packages_async).with(['foo', 'bar', 'baz'])
    @registry.sync_missing_packages_async
  end
  
  test 'sync_recently_updated_packages_async' do
    @registry.expects(:recently_updated_package_names_excluding_recently_synced).returns(['foo', 'bar', 'baz'])
    @registry.expects(:sync_packages_async).with(['foo', 'bar', 'baz'])
    @registry.sync_recently_updated_packages_async
  end
  
  test 'sync_packages' do
    @registry.expects(:sync_package).with('foo')
    @registry.expects(:sync_package).with('bar')
    @registry.sync_packages(['foo', 'bar'])
  end

  test 'sync_packages_async' do
    SyncPackageWorker.expects(:perform_bulk).with([[@registry.id, "foo"], [@registry.id, "bar"]])
    @registry.sync_packages_async(['foo', 'bar'])
  end

  test 'sync_package' do
    # TODO stub ecosystem_instance calls instead
    stub_request(:get, "https://rubygems.org/api/v1/gems/rubystats.json")
      .to_return({ status: 200, body: file_fixture('rubygems/rubystats.json') })
    stub_request(:get, "https://rubygems.org/api/v1/versions/rubystats.json")
      .to_return({ status: 200, body: file_fixture('rubygems/rubystats-versions.json') })
      stub_request(:head, "https://rubygems.org/api/v1/versions/rubystats.json")
      .to_return({ status: 200, body: file_fixture('rubygems/rubystats-versions.json') })
    stub_request(:get, "https://rubygems.org/api/v2/rubygems/rubystats/versions/0.3.0.json")
      .to_return({ status: 200, body: file_fixture('rubygems/0.3.0.json') })
    stub_request(:get, "https://rubygems.org/api/v2/rubygems/rubystats/versions/0.2.6.json")
      .to_return({ status: 200, body: file_fixture('rubygems/0.2.6.json') })
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/phillbaker/rubystats")
      .to_return({ status: 200, body: file_fixture('rubygems/lookup?url=https:%2F%2Fgithub.com%2Fphillbaker%2Frubystats'), headers: {content_type: 'application/json'} })
    stub_request(:get, "https://issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/phillbaker/rubystats")
      .to_return({ status: 200 })
    stub_request(:get, "https://issues.ecosyste.ms/api/v1/hosts/GitHub/repositories/phillbaker/rubystats/ping")
      .to_return({ status: 200 })

    package = @registry.sync_package('rubystats')
    package.reload
    assert package.id
    assert_equal package.name, 'rubystats'
    assert_equal package.registry, @registry
    assert_equal package.versions.length, 2
    assert_equal package.versions.sort.first.dependencies.length, 2
    assert_equal package.versions.sort.last.dependencies.length, 1
  end

  test 'sync_package_async' do
    SyncPackageWorker.expects(:perform_async).with(@registry.id, 'split')
    @registry.sync_package_async('split')
  end

  test 'sync_all_recently_updated_packages_async' do
    @registry.expects(:sync_recently_updated_packages_async).returns(true)
    Registry.stubs(:not_docker).returns([@registry])
    Registry.sync_all_recently_updated_packages_async
  end

  test 'Registry.sync_all_packages_async' do
    @registry.expects(:sync_all_packages_async).returns(true)
    Registry.stubs(:not_docker).returns([@registry])
    Registry.sync_all_packages_async
  end

  test 'sync_package does not trigger N+1 when checking for existing dependencies' do
    # Create package with existing versions that have dependencies
    package = @registry.packages.create!(name: 'test-package', ecosystem: @registry.ecosystem)

    # Create 10 versions with dependencies
    10.times do |i|
      version = package.versions.create!(
        number: "1.0.#{i}",
        published_at: Time.now - i.days,
        registry_id: @registry.id
      )
      version.dependencies.create!(
        package_name: "dependency-#{i}",
        requirements: "~> 1.0",
        kind: "runtime",
        ecosystem: @registry.ecosystem
      )
    end

    # Stub HTTP requests
    stub_request(:head, "https://rubygems.org/api/v1/versions/test-package.json")
      .to_return(status: 200, body: "", headers: {})

    # Mock the ecosystem_instance to return new versions
    ecosystem = @registry.ecosystem_instance

    # Mock package_metadata
    package_metadata = {
      name: 'test-package',
      description: 'Test package',
      versions: ['1.0.0', '1.0.1', '1.0.2', '1.0.3', '1.0.4', '1.0.5', '1.0.6', '1.0.7', '1.0.8', '1.0.9', '1.0.10']
    }

    ecosystem.stubs(:package_metadata).returns(package_metadata)

    # Mock versions_metadata to return one new version
    ecosystem.stubs(:versions_metadata).returns([
      { number: '1.0.10', published_at: Time.now }
    ])

    # Mock dependencies_metadata
    ecosystem.stubs(:dependencies_metadata).returns([])

    # Track queries that check for dependencies
    dependency_check_queries = []
    ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      if sql.include?('dependencies') && sql.include?('version_id')
        dependency_check_queries << sql
      end
    end

    # Sync the package
    @registry.sync_package('test-package', force: true)

    ActiveSupport::Notifications.unsubscribe('sql.active_record')

    # We should have at most 2 queries related to dependencies:
    # 1. One query to fetch version IDs that have dependencies (the fix we added)
    # 2. Possibly one insert query for new dependencies
    # We should NOT have N individual queries checking if each version has dependencies
    assert dependency_check_queries.count < 5,
      "Expected less than 5 dependency-related queries, but got #{dependency_check_queries.count}. This suggests N+1 is still present."
  end

  test 'calculate_growth_stats uses incremental counting' do
    # Create packages across multiple years
    @registry.packages.create!(name: 'pkg1', ecosystem: @registry.ecosystem, first_release_published_at: Date.new(2020, 6, 15))
    @registry.packages.create!(name: 'pkg2', ecosystem: @registry.ecosystem, first_release_published_at: Date.new(2021, 3, 10))
    @registry.packages.create!(name: 'pkg3', ecosystem: @registry.ecosystem, first_release_published_at: Date.new(2021, 8, 20))

    @registry.calculate_growth_stats(force: true)

    stat_2020 = @registry.registry_growth_stats.find_by(year: 2020)
    stat_2021 = @registry.registry_growth_stats.find_by(year: 2021)

    # 2020: 1 new, 1 cumulative
    assert_equal 1, stat_2020.new_packages_count
    assert_equal 1, stat_2020.packages_count

    # 2021: 2 new, 3 cumulative (1 + 2)
    assert_equal 2, stat_2021.new_packages_count
    assert_equal 3, stat_2021.packages_count
  end

  test 'icon_url returns github avatar by default' do
    @registry.github = 'rubygems'
    assert_equal 'https://github.com/rubygems.png', @registry.icon_url
  end

  test 'icon_url returns metadata icon_url when present' do
    @registry.github = 'rubygems'
    @registry.metadata = {'icon_url' => 'https://example.com/custom-logo.png'}
    assert_equal 'https://example.com/custom-logo.png', @registry.icon_url
  end

  test 'calculate_growth_stats preserves running totals when skipping years' do
    # Create packages across multiple years
    @registry.packages.create!(name: 'pkg1', ecosystem: @registry.ecosystem, first_release_published_at: Date.new(2020, 6, 15))
    @registry.packages.create!(name: 'pkg2', ecosystem: @registry.ecosystem, first_release_published_at: Date.new(2021, 3, 10))

    # Calculate stats only up to 2021 by manually creating records
    @registry.registry_growth_stats.create!(year: 2020, packages_count: 1, new_packages_count: 1, versions_count: 0, new_versions_count: 0)
    @registry.registry_growth_stats.create!(year: 2021, packages_count: 2, new_packages_count: 1, versions_count: 0, new_versions_count: 0)

    # Add a package in 2022
    @registry.packages.create!(name: 'pkg3', ecosystem: @registry.ecosystem, first_release_published_at: Date.new(2022, 1, 5))

    # Run without force - should skip 2020, 2021 but calculate 2022 with correct running totals
    @registry.calculate_growth_stats(force: false)

    stat_2022 = @registry.registry_growth_stats.find_by(year: 2022)

    # Should pick up running total from skipped 2021 (2) and add new package
    assert_equal 1, stat_2022.new_packages_count
    assert_equal 3, stat_2022.packages_count
  end

end
