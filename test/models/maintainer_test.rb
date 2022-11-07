require "test_helper"

class MaintainerTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:registry)
    should have_many(:maintainerships)
    should have_many(:packages).through(:maintainerships)
  end
end
