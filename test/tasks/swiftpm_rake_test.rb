require 'test_helper'
require 'rake'

class SwiftpmRakeTest < ActiveSupport::TestCase
  setup do
    silence_warnings { Packages::Application.load_tasks } if Rake::Task.tasks.empty?
    Rake::Task['packages:normalize_swift_names'].reenable
    @registry = Registry.create!(name: 'Swiftpm.io', url: 'https://swiftpm.io', ecosystem: 'swiftpm')
    @package = @registry.packages.create!(name: 'github.com/Example/Library', ecosystem: 'swiftpm', metadata: {'default_branch' => 'main'})
    @version = @package.versions.create!(number: '1.0.0')
    @dependency = @version.dependencies.create!(package_name: @package.name, ecosystem: 'swiftpm', requirements: '1.0.0', package_id: @package.id)
  end

  test 'normalization defaults to a scoped dry run' do
    out, = capture_io { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id) }
    assert_includes out, 'packages: 1'
    assert_includes out, 'dependencies: 1'
    assert_includes out, 'applied: false'
    assert_equal({'default_branch' => 'main'}, @package.reload.metadata)
    assert_equal @package.name, @dependency.reload.package_name
  end

  test 'normalization preserves package names metadata requirements and links' do
    other = Registry.create!(name: 'Other Swift', url: 'https://swift.example.org', ecosystem: 'swiftpm')
    other_package = other.packages.create!(name: @package.name, ecosystem: 'swiftpm')
    other_dep = other_package.versions.create!(number: '1.0.0').dependencies.create!(package_name: @package.name, ecosystem: 'swiftpm', requirements: '*')
    gitlab = @version.dependencies.create!(package_name: 'gitlab.com/Example/Library', ecosystem: 'swiftpm', requirements: '*')
    mismatch = @version.dependencies.create!(package_name: @package.name, ecosystem: 'carthage', requirements: '*')

    out, = capture_io { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id, 'true') }
    assert_includes out, 'applied: true'
    assert_equal 'github.com/Example/Library', @package.reload.name
    assert_equal({'default_branch' => 'main', 'normalized_name' => 'github.com/example/library'}, @package.metadata)
    assert_equal 'github.com/example/library', @dependency.reload.package_name
    assert_equal @package.id, @dependency.package_id
    assert_equal '1.0.0', @dependency.requirements
    assert_nil other_package.reload.metadata['normalized_name']
    assert_equal @package.name, other_dep.reload.package_name
    assert_equal 'gitlab.com/Example/Library', gitlab.reload.package_name
    assert_equal @package.name, mismatch.reload.package_name

    Rake::Task['packages:normalize_swift_names'].reenable
    out, = capture_io { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id, 'true') }
    assert_includes out, 'packages: 0'
    assert_includes out, 'dependencies: 0'
  end

  test 'normalization skips colliding names and their dependencies while applying the rest' do
    duplicate = @registry.packages.create!(name: @package.name.downcase, ecosystem: 'swiftpm')
    unlinked = @version.dependencies.create!(package_name: @package.name, ecosystem: 'swiftpm', requirements: '*')
    unaffected = @registry.packages.create!(name: 'github.com/Other/Library', ecosystem: 'swiftpm')
    dependency = @version.dependencies.create!(package_name: unaffected.name, ecosystem: 'swiftpm', requirements: '*')

    out, = capture_io { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id) }
    assert_includes out, 'packages: 1'
    assert_includes out, 'dependencies: 1'
    assert_includes out, 'github.com/example/library'
    assert_includes out, 'applied: false'
    assert_nil unaffected.reload.metadata['normalized_name']
    assert_equal unaffected.name, dependency.reload.package_name

    Rake::Task['packages:normalize_swift_names'].reenable
    out, = capture_io { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id, 'true') }
    assert_includes out, 'github.com/example/library'
    assert_includes out, 'applied: true'
    assert_equal 3, @registry.packages.count
    assert_nil @package.reload.metadata['normalized_name']
    assert_nil duplicate.reload.metadata['normalized_name']
    assert_equal @package.name, @dependency.reload.package_name
    assert_equal @package.id, @dependency.package_id
    assert_equal @package.name, unlinked.reload.package_name
    unlinked.update_package_id
    assert_equal @package.id, unlinked.reload.package_id
    assert_equal 'github.com/other/library', unaffected.reload.metadata['normalized_name']
    assert_equal 'github.com/other/library', dependency.reload.package_name
  end

  test 'normalization updates dependencies through bounded version batches' do
    versions = Version.insert_all!((1..1000).map { |i| { package_id: @package.id, number: "1.0.#{i}" } }, returning: [:id])
    Dependency.insert_all!(versions.rows.map do |(id)|
      { version_id: id, package_name: @package.name, ecosystem: 'swiftpm', requirements: '*' }
    end)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      capture_io { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id, 'true') }
    end

    updates = queries.grep(/\AUPDATE "dependencies"/)
    assert_equal 2, updates.size
    updates.each { |sql| assert_match(/"dependencies"\."version_id" IN \(SELECT "versions"\."id"/, sql) }
    assert_empty queries.grep(/\ASELECT.*FROM "dependencies".*ORDER BY.*"id"/)
    assert_equal 1001, Dependency.where(version_id: @package.versions.select(:id), package_name: @package.name.downcase).count
  end

  test 'normalization refuses another ecosystem' do
    @registry.update!(ecosystem: 'carthage')
    assert_raises(ArgumentError) { Rake::Task['packages:normalize_swift_names'].invoke(@registry.id, 'true') }
  end
end
