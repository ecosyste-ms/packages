require 'test_helper'
require 'rake'

class DependencyAnalysisRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings do
        Packages::Application.load_tasks
      end
    end
  end

  test 'breaking changes compares cleaned available versions' do
    registry = Registry.create!(name: 'npmjs.org', url: 'https://registry.npmjs.org', ecosystem: 'npm')
    target = registry.packages.create!(name: 'target', ecosystem: 'npm')
    target.versions.create!(number: 'v2.0.0')
    dependent = registry.packages.create!(name: 'dependent', ecosystem: 'npm')
    version = dependent.versions.create!(number: '1.0.0')
    version.dependencies.create!(package_name: target.name, ecosystem: 'npm', requirements: '~10.0.0')

    task = Rake::Task['dependency_analysis:breaking_changes']
    task.reenable
    output = capture_io { task.invoke('false', '1', 'npm') }.first

    assert_includes output, 'Found 0 breaking change candidates.'
  end
end
