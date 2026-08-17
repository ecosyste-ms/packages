require "test_helper"
require "yaml"

class SidekiqConfigTest < ActiveSupport::TestCase
  test "polls every queue with weighted priority" do
    config = YAML.load_file(Rails.root.join("config/sidekiq.yml"))

    assert_equal [["critical", 10], ["default", 3], ["low", 1]], config.fetch(:queues)
  end
end
