require "test_helper"
require "yaml"

class SidekiqConfigTest < ActiveSupport::TestCase
  test "polls every queue with weighted priority" do
    config = YAML.load_file(Rails.root.join("config/sidekiq.yml"))

    assert_equal [["critical", 10], ["default", 3], ["low", 2], ["repo_metadata", 1], ["versions", 1]], config.fetch(:queues)
  end
end
