require "test_helper"

class OpenapiTest < ActiveSupport::TestCase
  test 'openapi.yaml is valid' do
    f = YAML.load_file(Rails.root.join('openapi/api/v1/openapi.yaml'))
    assert_equal f.class, Hash
  end
end