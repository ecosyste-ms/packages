require "test_helper"

class RubygemsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @ecosystem = Ecosystem::Rubygems.new(@registry.url)
    @package = Package.new(ecosystem: 'rubygems', name: 'rails')
    @version = @package.versions.build(number: '7.0.0')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://rubygems.org/gems/rails'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://rubygems.org/gems/rails/versions/7.0.0'
  end

  test 'download_url' do
    package_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal package_url, 'https://rubygems.org/downloads/rails-7.0.0.gem'
  end

  test 'documentation_url' do
    package_url = @ecosystem.documentation_url(@package.name)
    assert_equal package_url, 'http://www.rubydoc.info/gems/rails/'
  end

  test 'documentation_url with version' do
    package_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal package_url, 'http://www.rubydoc.info/gems/rails/7.0.0'
  end

  test 'install_command' do
    package_url = @ecosystem.install_command(@package)
    assert_equal package_url, 'gem install rails -s https://rubygems.org'
  end

  test 'install_command with version' do
    package_url = @ecosystem.install_command(@package, @version.number)
    assert_equal package_url, 'gem install rails -s https://rubygems.org -v 7.0.0'
  end

  test 'check_status_url' do
    package_url = @ecosystem.check_status_url(@package)
    assert_equal package_url, "https://rubygems.org/api/v1/versions/rails.json"
  end

  test 'all_package_names' do
    stub_request(:get, "https://rubygems.org/specs.4.8.gz")
      .to_return({ status: 200, body: file_fixture('rubygems/specs.4.8.gz') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 168761
    assert_equal all_package_names.last, 'zzzzzz'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://rubygems.org/api/v1/activity/just_updated.json")
      .to_return({ status: 200, body: file_fixture('rubygems/just_updated.json') })
    stub_request(:get, "https://rubygems.org/api/v1/activity/latest.json")
      .to_return({ status: 200, body: file_fixture('rubygems/latest.json') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 84
    assert_equal recently_updated_package_names.last, 'reparse'
  end

  test 'package_metadata' do
    skip("To be implemented")
  end

  test 'fetch_package_metadata' do
    skip("To be implemented")
  end

  test 'map_package_metadata' do
    skip("To be implemented")
  end
end
