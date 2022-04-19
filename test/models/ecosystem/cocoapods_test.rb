require "test_helper"

class CocoapodsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Cocoapod.org', url: 'https://cocoapods.org', ecosystem: 'cocoapods')
    @ecosystem = Ecosystem::Cocoapods.new(@registry.url)
    @package = Package.new(ecosystem: 'cocoapods', name: 'Foo')
    @version = @package.versions.build(number: '0.8.5')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://cocoapods.org/pods/Foo'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'https://cocoapods.org/pods/Foo'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://cocoadocs.org/docsets/Foo/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
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
    stub_request(:get, "https://github.com/CocoaPods/Specs/commits/master.atom")
      .to_return({ status: 200, body: file_fixture('cocoapods/master.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 19
    assert_equal recently_updated_package_names.last, 'VerifaiNFC'
  end

  test 'package_metadata' do
    stub_request(:get, "https://cdn.cocoapods.org/all_pods_versions_1_3_5.txt")
      .to_return({ status: 200, body: file_fixture('cocoapods/all_pods_versions_1_3_5.txt') })
    stub_request(:get, "https://cdn.cocoapods.org/Specs/1/3/5/Foo/1.1.3/Foo.podspec.json")
      .to_return({ status: 200, body: file_fixture('cocoapods/Foo.podspec.json') })
    package_metadata = @ecosystem.package_metadata('Foo')
    
    assert_equal package_metadata[:name], "Foo"
    assert_equal package_metadata[:description], "This is a iOS framework containing both objective c and swift code"
    assert_equal package_metadata[:homepage], "https://github.com/deepesh259nitk/mixedFramework"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/deepesh259nitk/mixedFramework"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://cdn.cocoapods.org/all_pods_versions_1_3_5.txt")
      .to_return({ status: 200, body: file_fixture('cocoapods/all_pods_versions_1_3_5.txt') })
    stub_request(:get, "https://cdn.cocoapods.org/Specs/1/3/5/Foo/1.1.3/Foo.podspec.json")
      .to_return({ status: 200, body: file_fixture('cocoapods/Foo.podspec.json') })
    package_metadata = @ecosystem.package_metadata('Foo')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"1.0.7"}, {:number=>"1.0.9"}, {:number=>"1.1.0"}, {:number=>"1.1.1"}, {:number=>"1.1.2"}, {:number=>"1.1.3"}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://cdn.cocoapods.org/Specs/2/2/2/AppNetworkManager/1.0.0/AppNetworkManager.podspec.json")
      .to_return({ status: 200, body: file_fixture('cocoapods/AppNetworkManager.podspec.json') })
    
    dependencies_metadata = @ecosystem.dependencies_metadata('AppNetworkManager', '1.0.0', {})
    
    assert_equal dependencies_metadata, [
      {:package_name=>"HandyJSON", :requirements=>"~> 5.0.0", :kind=>"runtime", :ecosystem=>"cocoapods"},
      {:package_name=>"Moya/RxSwift", :requirements=>"~> 13.0.1", :kind=>"runtime", :ecosystem=>"cocoapods"},
      {:package_name=>"RxSwift", :requirements=>"~>4.5.0", :kind=>"runtime", :ecosystem=>"cocoapods"},
      {:package_name=>"RxCocoa", :requirements=>"~>4.5.0", :kind=>"runtime", :ecosystem=>"cocoapods"}
    ]
  end
end
