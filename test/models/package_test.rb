require "test_helper"

class PackageTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:registry)
    should have_many(:dependencies)
    should have_many(:versions)
  end

  context 'validations' do
    should validate_presence_of(:registry_id)
    should validate_presence_of(:name)
    should validate_presence_of(:ecosystem)
    should validate_uniqueness_of(:name).scoped_to(:registry_id)
  end

  setup do
    @registry = Registry.create(default: true, name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @package = @registry.packages.create(name: 'foo', ecosystem: @registry.ecosystem, licenses: 'mit')
    @version = @package.versions.create(number: '1.0.0', published_at: 1.month.ago)
    @version2 = @package.versions.create(number: '2.0.0', published_at: 1.week.ago)
  end

  test 'update_details' do
    @package.expects(:normalize_licenses).returns(true)
    @package.expects(:set_latest_release_published_at).returns(true)
    @package.expects(:set_latest_release_number).returns(true)
    @package.update_details
  end

  test 'normalize_licenses' do
    @package.normalize_licenses
    assert_equal @package.normalized_licenses, ["MIT"]
  end

  test 'set_latest_release_published_at' do
    @package.set_latest_release_published_at
    assert_equal @package.latest_release_published_at, @version2.published_at
  end

  test 'set_latest_release_number' do
    @package.set_latest_release_number
    assert_equal @package.latest_release_number, '2.0.0'
  end

  test 'install_command' do
    assert_equal @package.install_command, 'gem install foo -s https://rubygems.org'
  end

  test 'registry_url' do
    assert_equal @package.registry_url, 'https://rubygems.org/gems/foo'
  end

  test 'documentation_url' do
    assert_equal @package.documentation_url, "http://www.rubydoc.info/gems/foo/"
  end

  test 'purl' do
    assert_equal @package.purl, "pkg:gem/foo"
  end

  test 'with_advisories scope' do
    package_with_advisories = @registry.packages.create(name: 'bar', ecosystem: @registry.ecosystem, advisories: [{ 'id' => 'CVE-2024-1234' }])
    package_without_advisories = @registry.packages.create(name: 'baz', ecosystem: @registry.ecosystem, advisories: [])

    results = Package.with_advisories

    assert_includes results, package_with_advisories
    refute_includes results, package_without_advisories
    refute_includes results, @package
  end
end
