require "test_helper"

class ExportTest < ActiveSupport::TestCase
  context 'validations' do
    should validate_presence_of(:date)
    should validate_presence_of(:bucket_name)
    should validate_presence_of(:packages_count)
  end
end
