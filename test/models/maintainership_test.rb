require "test_helper"

class MaintainershipTest < ActiveSupport::TestCase
  context 'associations' do
    should belong_to(:maintainer)
    should belong_to(:package)
  end
end
