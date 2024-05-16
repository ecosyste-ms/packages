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
end
