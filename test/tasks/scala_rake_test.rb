require 'test_helper'
require 'rake'

class ScalaRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings { Packages::Application.load_tasks }
    end
    @registry = Registry.create!(name: 'repo1.maven.org', url: 'https://repo1.maven.org/maven2', ecosystem: 'maven')
  end

  teardown do
    ENV.delete('REGISTRY')
    ENV.delete('LIMIT')
  end

  test "scala_strip_suffix collapses cross-build suffixes" do
    assert_equal 'org.typelevel:cats-core', scala_strip_suffix('org.typelevel:cats-core_2.13')
    assert_equal 'org.typelevel:cats-core', scala_strip_suffix('org.typelevel:cats-core_3')
    assert_equal 'org.typelevel:cats-core', scala_strip_suffix('org.typelevel:cats-core_sjs1_2.13')
    assert_equal 'org.typelevel:cats-core', scala_strip_suffix('org.typelevel:cats-core_native0.4_3')
    assert_equal 'org.slf4j:slf4j-api', scala_strip_suffix('org.slf4j:slf4j-api')
    assert_equal 'com.foo:bar_baz', scala_strip_suffix('com.foo:bar_baz')
    assert_equal 'no-colon', scala_strip_suffix('no-colon')
  end

  test "export_dependencies ranks collapsed deps by distinct scala source repos" do
    cats = @registry.packages.create!(name: 'org.typelevel:cats-core_2.13', ecosystem: 'maven',
                                       repository_url: 'https://github.com/typelevel/cats')
    zio  = @registry.packages.create!(name: 'dev.zio:zio_3', ecosystem: 'maven',
                                       repository_url: 'https://github.com/zio/zio')
    slf4j = @registry.packages.create!(name: 'org.slf4j:slf4j-api', ecosystem: 'maven',
                                        repository_url: 'https://github.com/qos-ch/slf4j',
                                        dependent_packages_count: 999,
                                        repo_metadata: { 'language' => 'Java', 'stargazers_count' => 10 })
    stest = @registry.packages.create!(name: 'org.scalatest:scalatest_2.13', ecosystem: 'maven',
                                        repository_url: 'https://github.com/scalatest/scalatest',
                                        dependent_packages_count: 50,
                                        repo_metadata: { 'language' => 'Scala' })

    v_cats = cats.versions.create!(number: '2.9.0', registry: @registry, latest: true)
    v_zio  = zio.versions.create!(number: '2.0.0', registry: @registry, latest: true)

    Dependency.create!(version_id: v_cats.id, ecosystem: 'maven', package_name: 'org.slf4j:slf4j-api', requirements: '1.7.0')
    Dependency.create!(version_id: v_cats.id, ecosystem: 'maven', package_name: 'org.scalatest:scalatest_2.13', requirements: '3.2.0')
    Dependency.create!(version_id: v_zio.id,  ecosystem: 'maven', package_name: 'org.slf4j:slf4j-api', requirements: '1.7.0')
    Dependency.create!(version_id: v_zio.id,  ecosystem: 'maven', package_name: 'org.scalatest:scalatest_3', requirements: '3.2.0')

    out, _ = capture_io { Rake::Task['scala:export_dependencies'].execute }
    rows = CSV.parse(out, headers: true)

    assert_equal 2, rows.size
    by_name = rows.map { |r| [r['logical_name'], r] }.to_h

    assert by_name.key?('org.slf4j:slf4j-api')
    assert by_name.key?('org.scalatest:scalatest')
    assert_equal '2', by_name['org.slf4j:slf4j-api']['scala_dependent_projects']
    assert_equal '2', by_name['org.scalatest:scalatest']['scala_dependent_projects']
    assert_equal 'Java', by_name['org.slf4j:slf4j-api']['language']
    assert_equal 'Scala', by_name['org.scalatest:scalatest']['language']
    assert_equal '999', by_name['org.slf4j:slf4j-api']['total_dependent_packages']
  end

  test "export_projects groups scala artifacts by repository_url" do
    @registry.packages.create!(name: 'org.typelevel:cats-core_2.13', ecosystem: 'maven',
                               repository_url: 'https://github.com/typelevel/cats',
                               dependent_packages_count: 100,
                               repo_metadata: { 'language' => 'Scala', 'stargazers_count' => 5000 })
    @registry.packages.create!(name: 'org.typelevel:cats-core_3', ecosystem: 'maven',
                               repository_url: 'https://github.com/typelevel/cats',
                               dependent_packages_count: 40)
    @registry.packages.create!(name: 'org.typelevel:cats-kernel_2.13', ecosystem: 'maven',
                               repository_url: 'https://github.com/typelevel/cats',
                               dependent_packages_count: 10)
    @registry.packages.create!(name: 'com.example:javaonly', ecosystem: 'maven',
                               repository_url: 'https://github.com/example/java',
                               repo_metadata: { 'language' => 'Java' })

    out, _ = capture_io { Rake::Task['scala:export_projects'].execute }
    rows = CSV.parse(out, headers: true)

    assert_equal 1, rows.size
    r = rows.first
    assert_equal 'https://github.com/typelevel/cats', r['repository_url']
    assert_equal '3', r['artifact_count']
    assert_equal '150', r['total_dependent_packages']
    assert_equal 'org.typelevel', r['group_ids']
    assert_equal 'Scala', r['language']
  end
end
