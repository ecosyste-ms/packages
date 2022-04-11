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
    @registry = Registry.create(name: 'foo.com', url: 'https://foo.com', ecosystem: 'npm')
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

  test 'update_details before_save' do
    @package.expects(:update_details).returns(true)
    @package.save
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
end
