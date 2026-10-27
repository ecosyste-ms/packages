require "test_helper"
require "yaml"

class SidekiqConfigTest < ActiveSupport::TestCase
  test "import workers do not poll the dependent count queue" do
    config = YAML.load_file(Rails.root.join("config/sidekiq.yml"))

    assert_equal [["critical", 10], ["default", 3], ["low", 2], ["repo_metadata", 1], ["versions", 1]], config.fetch(:queues)
  end

  test 'count workers have one thread and only poll dependent counts' do
    config = YAML.load_file(Rails.root.join('config/sidekiq_counts.yml'))
    assert_equal 1, config.fetch(:concurrency)
    assert_equal ['dependent_counts'], config.fetch(:queues)
    assert_includes File.read(Rails.root.join('Procfile')), 'counts: bundle exec sidekiq -C config/sidekiq_counts.yml'
  end
end
