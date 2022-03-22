require "test_helper"

class DependencyTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:package).optional 
    should belong_to(:version)
  end

  context 'validations' do
    should validate_presence_of(:package_name)
    should validate_presence_of(:version_id)
    should validate_presence_of(:requirements)
    should validate_presence_of(:ecosystem)
  end
end
