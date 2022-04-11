require "test_helper"

class VersionTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:package)
    should have_many(:dependencies)
  end

  context 'validations' do
    should validate_presence_of(:package_id)
    should validate_presence_of(:number)
    should validate_uniqueness_of(:number).scoped_to(:package_id)
  end

  setup do 
    @version = Version.new(number: '1.0.0', created_at: Time.now)
    @version2 = Version.new(number: '2.0.0', created_at: 1.week.ago)
  end

  test 'published_at' do
    assert_equal @version.published_at, @version.created_at
  end

  test 'sort' do
    sorted = [@version, @version2].sort
    assert_equal sorted.first, @version2
  end
  
  test 'to_s' do
    assert_equal @version.to_s, @version.number
  end

  test 'semantic_version' do
    assert_equal @version.semantic_version.class, Semantic::Version
  end
end
