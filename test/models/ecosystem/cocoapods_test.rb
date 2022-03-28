require "test_helper"

class CocoapodsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Cocoapod.org', url: 'https://cocoapods.org', ecosystem: 'Cocoapods')
    @ecosystem = Ecosystem::Cocoapods.new(@registry.url)
    @package = Package.new(ecosystem: 'Cocoapods', name: 'Foo')
    @version = @package.versions.build(number: '0.8.5')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://cocoapods.org/pods/Foo'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://cocoapods.org/pods/Foo'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, "https://cocoadocs.org/docsets/Foo/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, "https://cocoadocs.org/docsets/Foo/0.8.5"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'pod try Foo'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'pod try Foo'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://cocoapods.org/pods/Foo"
  end

  test 'all_package_names' do
    stub_request(:get, "https://cdn.cocoapods.org/all_pods.txt")
      .to_return({ status: 200, body: file_fixture('cocoapods/all_pods.txt') })
    all_package_names = @ecosystem.all_package_names

    assert_equal all_package_names.length, 85191
    assert_equal all_package_names.last, '🕕'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "http://cocoapods.libraries.io/feed.rss")
      .to_return({ status: 200, body: file_fixture('cocoapods/feed.rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 16
    assert_equal recently_updated_package_names.last, 'Drivit'
  end

  test 'package_metadata' do
    stub_request(:get, "http://cocoapods.libraries.io/pods/Foo.json")
      .to_return({ status: 200, body: file_fixture('cocoapods/Foo.json') })
    package_metadata = @ecosystem.package_metadata('Foo')
    
    assert_equal package_metadata[:name], "Foo"
    assert_equal package_metadata[:description], "This is a iOS framework containing both objective c and swift code"
    assert_equal package_metadata[:homepage], "https://github.com/deepesh259nitk/mixedFramework"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/deepesh259nitk/mixedFramework"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "http://cocoapods.libraries.io/pods/Foo.json")
      .to_return({ status: 200, body: file_fixture('cocoapods/Foo.json') })
    package_metadata = @ecosystem.package_metadata('Foo')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"1.0.9"}, {:number=>"1.1.0"}, {:number=>"1.1.3"}, {:number=>"1.1.2"}, {:number=>"1.1.1"}, {:number=>"1.0.7"}]
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('Foo', '0.1.0', nil)
    
    assert_equal dependencies_metadata, []
  end
end
