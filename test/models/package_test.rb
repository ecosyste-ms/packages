require "test_helper"

class PackageTest < ActiveSupport::TestCase
  context 'associations' do
    should have_many(:dependencies)
    should have_many(:versions)
  end

  context 'validations' do
    should validate_presence_of(:registry_id)
    should validate_presence_of(:name)
    should validate_presence_of(:ecosystem)
    # TODO validates_uniqueness_of :name, scope: :ecosystem, case_sensitive: true
  end
end
