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
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://rubygems.org/downloads/rails-7.0.0.gem'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, 'http://www.rubydoc.info/gems/rails/'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, 'http://www.rubydoc.info/gems/rails/7.0.0'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'gem install rails -s https://rubygems.org'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'gem install rails -s https://rubygems.org -v 7.0.0'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://rubygems.org/api/v1/versions/rails.json"
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
    stub_request(:get, "https://rubygems.org/api/v1/gems/rubystats.json")
      .to_return({ status: 200, body: file_fixture('rubygems/rubystats.json') })
    package_metadata = @ecosystem.package_metadata('rubystats')

    assert_equal package_metadata, {:name=>"rubystats",
      :description=>"Ruby Stats is a port of the statistics libraries from PHPMath. Probability distributions include binomial, beta, and normal distributions with PDF, CDF and inverse CDF as well as Fisher's Exact Test.", 
      :homepage=>"https://github.com/phillbaker/rubystats", 
      :licenses=>"MIT", 
      :repository_url=>"https://github.com/phillbaker/rubystats"
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "https://rubygems.org/api/v1/versions/rubystats.json")
      .to_return({ status: 200, body: file_fixture('rubygems/rubystats-versions.json') })
    versions_metadata = @ecosystem.versions_metadata({name: 'rubystats'})

    assert_equal versions_metadata, [
      {:number=>"0.3.0", :published_at=>"2017-12-02T17:23:59.896Z", :licenses=>"MIT"},
      {:number=>"0.2.6", :published_at=>"2017-07-24T11:40:49.445Z", :licenses=>"MIT"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://rubygems.org/api/v2/rubygems/rubystats/versions/0.3.0.json")
      .to_return({ status: 200, body: file_fixture('rubygems/0.3.0.json') })
    dependencies_metadata = @ecosystem.dependencies_metadata('rubystats', '0.3.0', nil)
    
    assert_equal dependencies_metadata, [
      {:package_name=>"hoe", :requirements=>">= 1.7.0", :kind=>"Development", :ecosystem=>"rubygems"},
      {:package_name=>"minitest", :requirements=>"< 5.0, >= 4.2", :kind=>"Development", :ecosystem=>"rubygems"}
    ]
  end
end
