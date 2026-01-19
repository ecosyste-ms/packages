require 'test_helper'
require 'rake'
require 'csv'

class NcsuVerificationRakeTest < ActiveSupport::TestCase
  setup do
    if Rake::Task.tasks.empty?
      silence_warnings do
        Packages::Application.load_tasks
      end
    end

    Rake::Task['ncsu:verify_counts'].reenable
    Rake::Task['ncsu:export_packages'].reenable
    Rake::Task['ncsu:export_csv'].reenable

    @registry = Registry.create(
      default: true,
      name: 'rubygems.org',
      url: 'https://rubygems.org',
      ecosystem: 'rubygems'
    )

    @old_date = Date.new(2020, 1, 1)
    @recent_date = Date.new(2024, 1, 1)
  end

  test 'verify_counts runs without error for empty registry' do
    assert_nothing_raised do
      Rake::Task['ncsu:verify_counts'].invoke('rubygems')
    end
  end

  test 'export_packages writes CSV with package names and repository URLs' do
    create_qualifying_package('test-export-package')
    output_file = Rails.root.join('tmp', 'test_export.csv').to_s

    Rake::Task['ncsu:export_packages'].invoke('rubygems', output_file)

    assert File.exist?(output_file)
    csv_content = CSV.read(output_file)
    assert_equal ['package_name', 'repository_url'], csv_content[0]

    package_row = csv_content.find { |row| row[0] == 'test-export-package' }
    assert_not_nil package_row
    assert_equal 'https://github.com/user/test-export-package', package_row[1]
  ensure
    File.delete(output_file) if File.exist?(output_file)
  end

  test 'export_packages creates empty CSV when no packages match' do
    output_file = Rails.root.join('tmp', 'test_export_empty.csv').to_s

    Rake::Task['ncsu:export_packages'].reenable
    Rake::Task['ncsu:export_packages'].invoke('rubygems', output_file)

    assert File.exist?(output_file)
    csv_content = CSV.read(output_file)
    assert_equal 1, csv_content.length
    assert_equal ['package_name', 'repository_url'], csv_content[0]
  ensure
    File.delete(output_file) if File.exist?(output_file)
  end

  test 'export_csv outputs CSV to stdout' do
    create_qualifying_package('test-stdout-package')

    Rake::Task['ncsu:export_csv'].reenable

    output = capture_io do
      Rake::Task['ncsu:export_csv'].invoke('rubygems')
    end

    stdout_output = output[0]
    csv_content = CSV.parse(stdout_output)

    assert_equal ['package_name', 'repository_url'], csv_content[0]
    package_row = csv_content.find { |row| row[0] == 'test-stdout-package' }
    assert_not_nil package_row
    assert_equal 'https://github.com/user/test-stdout-package', package_row[1]
  end

  def create_package(attrs = {})
    @registry.packages.create!({
      ecosystem: @registry.ecosystem,
      status: nil
    }.merge(attrs))
  end

  def create_qualifying_package(name)
    package = create_package(
      name: name,
      first_release_published_at: @old_date,
      repository_url: "https://github.com/user/#{name}",
      dependent_packages_count: 5,
      latest_release_number: 'v1.0.0',
      latest_release_published_at: @recent_date,
      repo_metadata: { 'tags' => [{ 'name' => 'v1.0.0' }, { 'name' => 'v0.9.0' }] }
    )

    version1 = package.versions.create!(
      number: '1.0.0',
      published_at: @recent_date,
      latest: true
    )
    package.versions.create!(
      number: '0.9.0',
      published_at: @recent_date - 1.month,
      latest: false
    )

    Dependency.create!(
      version_id: version1.id,
      package_name: 'some-dependency',
      requirements: '>= 0',
      ecosystem: @registry.ecosystem
    )

    package
  end
end
