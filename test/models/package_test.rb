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
end
