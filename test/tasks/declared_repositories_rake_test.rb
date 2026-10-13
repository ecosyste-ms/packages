require 'test_helper'
require 'rake'

class DeclaredRepositoriesRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings { Packages::Application.load_tasks }
    end
    Rake::Task['packages:declared_repositories'].reenable
    Rake::Task['packages:sync_declared_dependencies'].reenable
  end

  test 'declared_repositories prints untracked repositories with unresolved dependency counts' do
    central = Registry.create!(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven')
    package = central.packages.create!(name: 'com.example:app', namespace: 'com.example', ecosystem: 'maven', metadata: { 'repositories' => ['https://repo.osgeo.org/repository/release/'] })
    version = package.versions.create!(number: '1.0', latest: true, registry_id: central.id)
    version.dependencies.create!(package_name: 'org.geotools:gt-main', ecosystem: 'maven', requirements: '30.0', package_id: package.id)

    out, _err = capture_io { Rake::Task['packages:declared_repositories'].invoke('maven') }

    assert_includes out, "=== untracked repositories ===\nnamespaces\tunresolved\trepo\n1\t1\trepo.osgeo.org/repository/release\n"
  end

  test 'sync_declared_dependencies queues declared dependencies for Maven registries only' do
    SyncPackageWorker.clear
    central = Registry.create!(name: 'repo1.maven.org', url: 'https://maven-central.storage-download.googleapis.com/maven2', ecosystem: 'maven',
                               metadata: { 'aliases' => ['https://repo1.maven.org/maven2'] })
    Registry.create!(name: 'rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    package = central.packages.create!(name: 'com.example:app', namespace: 'com.example', ecosystem: 'maven', metadata: { 'repositories' => ['https://repo1.maven.org/maven2/'] })
    version = package.versions.create!(number: '1.0', latest: true, registry_id: central.id)
    version.dependencies.create!(package_name: 'org.example:missing', ecosystem: 'maven', requirements: '1.0', package_id: package.id)

    out, _err = capture_io { Rake::Task['packages:sync_declared_dependencies'].invoke }

    assert_equal "repo1.maven.org: 1\n", out
    assert_equal [[central.id, 'org.example:missing']], SyncPackageWorker.jobs.map { |job| job['args'] }
  end
end
