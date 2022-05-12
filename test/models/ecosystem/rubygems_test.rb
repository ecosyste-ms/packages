require "test_helper"

class RubygemsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Rubygems.org', url: 'https://rubygems.org', ecosystem: 'rubygems')
    @ecosystem = Ecosystem::Rubygems.new(@registry.url)
    @package = Package.new(ecosystem: 'rubygems', name: 'nokogiri')
    @version = @package.versions.build(number: '1.13.6')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://rubygems.org/gems/nokogiri'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://rubygems.org/gems/nokogiri/versions/1.13.6'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://rubygems.org/downloads/nokogiri-1.13.6.gem'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'http://www.rubydoc.info/gems/nokogiri/'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, 'http://www.rubydoc.info/gems/nokogiri/1.13.6'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'gem install nokogiri -s https://rubygems.org'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'gem install nokogiri -s https://rubygems.org -v 1.13.6'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://rubygems.org/api/v1/versions/nokogiri.json"
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
    stub_request(:get, "https://rubygems.org/api/v1/gems/nokogiri.json")
      .to_return({ status: 200, body: file_fixture('rubygems/nokogiri.json') })
    package_metadata = @ecosystem.package_metadata('nokogiri')

    assert_equal package_metadata, {
      :name=>"nokogiri", 
      :description=>"Nokogiri (鋸) makes it easy and painless to work with XML and HTML from Ruby. It provides a\nsensible, easy-to-understand API for reading, writing, modifying, and querying documents. It is\nfast and standards-compliant by relying on native parsers like libxml2 (C) and xerces (Java).\n", 
      :homepage=>"https://nokogiri.org",
      :licenses=>"MIT",
      :repository_url=>"https://github.com/sparklemotion/nokogiri"
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "https://rubygems.org/api/v1/versions/nokogiri.json")
      .to_return({ status: 200, body: file_fixture('rubygems/nokogiri-versions.json') })
    versions_metadata = @ecosystem.versions_metadata({name: 'nokogiri'})

    assert_equal versions_metadata.first, {:number=>"1.13.6", :published_at=>"2022-05-08T14:34:51.113Z", :licenses=>"MIT", :integrity=>"sha256-b1512fdc0aba446e1ee30de3e0671518eb363e75fab53486e99e8891d44b8587", :metadata=>{:platform=>"ruby"}}
    assert_equal versions_metadata.second, {:number=>"1.13.6-x86_64-linux", :published_at=>"2022-05-08T14:34:45.502Z", :licenses=>"MIT", :integrity=>"sha256-3fa37b0c3b5744af45f9da3e4ae9cbd89480b35e12ae36b5e87a0452e0b38335", :metadata=>{:platform=>"x86_64-linux"}}
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://rubygems.org/api/v2/rubygems/nokogiri/versions/0.3.0.json")
      .to_return({ status: 200, body: file_fixture('rubygems/0.3.0.json') })
    dependencies_metadata = @ecosystem.dependencies_metadata('nokogiri', '0.3.0', nil)
    
    assert_equal dependencies_metadata, [
      {:package_name=>"hoe", :requirements=>">= 1.7.0", :kind=>"Development", :ecosystem=>"rubygems"},
      {:package_name=>"minitest", :requirements=>"< 5.0, >= 4.2", :kind=>"Development", :ecosystem=>"rubygems"}
    ]
  end
end
