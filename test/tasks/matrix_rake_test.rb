require 'test_helper'
require 'rake'

class MatrixRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings do
        Packages::Application.load_tasks
      end
    end
  end

  test "export outputs the FOSDEM package metrics as CSV" do
    registry = Registry.create!(
      name: 'matrix.example',
      url: 'https://matrix.example',
      ecosystem: 'matrix-test'
    )
    registry.packages.create!(
      name: 'example',
      ecosystem: 'matrix-test',
      downloads: 12_345,
      dependent_repos_count: 234,
      dependent_packages_count: 56,
      docker_downloads_count: 7_890,
      docker_dependents_count: 12,
      repo_metadata: {
        'stargazers_count' => 345,
        'forks_count' => 67
      }
    )

    output = capture_io { Rake::Task["matrix:export"].execute }.first
    rows = CSV.parse(output, headers: true)
    row = rows.find { |csv_row| csv_row['Ecosystem'] == 'matrix-test' }

    assert_equal [
      'Ecosystem',
      'Downloads',
      'dependent_repos_count',
      'stargazers_count',
      'forks_count',
      'dependent_packages_count',
      'docker_downloads_count',
      'docker_dependents_count'
    ], rows.headers
    assert_equal '12345', row['Downloads']
    assert_equal '234', row['dependent_repos_count']
    assert_equal '345', row['stargazers_count']
    assert_equal '67', row['forks_count']
    assert_equal '56', row['dependent_packages_count']
    assert_equal '7890', row['docker_downloads_count']
    assert_equal '12', row['docker_dependents_count']
  end
end
