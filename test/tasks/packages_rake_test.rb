require 'test_helper'
require 'rake'

class PackagesRakeTest < ActiveSupport::TestCase
  setup do
    # Only load tasks if they haven't been loaded yet, and suppress stats warning
    if Rake::Task.tasks.empty?
      # Suppress the STATS_DIRECTORIES redefinition warning when loading tasks in tests
      silence_warnings do
        Packages::Application.load_tasks
      end
    end
  end

  test "should sync recent packages" do
    Registry.expects(:sync_all_recently_updated_packages_async).returns(:true)
    Rake::Task["packages:sync_recent"].invoke
  end

  test "should sync all packages" do
    Registry.expects(:sync_all_packages).returns(:true)
    Rake::Task["packages:sync_all"].invoke
  end

  test "should sync least recently synced packages" do
    Package.expects(:sync_least_recent_async).returns(:true)
    Rake::Task["packages:sync_least_recent"].invoke
  end
end