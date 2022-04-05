require 'test_helper'
require 'rake'

class PackagesRakeTest < ActiveSupport::TestCase
  setup do
    Packages::Application.load_tasks if Rake::Task.tasks.empty?
  end

  test "should sync recent packages" do
    Registry.expects(:sync_all_recently_updated_packages_async).returns(:true)
    Rake::Task["packages:sync_recent"].invoke
  end
end