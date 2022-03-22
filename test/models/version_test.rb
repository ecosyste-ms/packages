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
end
