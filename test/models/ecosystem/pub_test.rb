require "test_helper"

class PubTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Pub.dev', url: 'https://pub.dev', ecosystem: 'pub')
    @ecosystem = Ecosystem::Pub.new(@registry.url)
    @package = Package.new(ecosystem: 'pub', name: 'bloc')
    @version = @package.versions.build(number: '8.0.3')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://pub.dev/packages/bloc'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://pub.dev/packages/bloc/versions/8.0.3'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://pub.dev/packages/bloc/versions/8.0.3.tar.gz'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, 'https://pub.dev/documentation/bloc/'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, 'https://pub.dev/documentation/bloc/8.0.3'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'dart pub add bloc'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'dart pub add bloc:8.0.3'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://pub.dev/packages/bloc"
  end

  test 'all_package_names' do
    stub_request(:get, "https://pub.dev/api/packages?page=1")
      .to_return({ status: 200, body: file_fixture('pub/packages?page=1') })
    stub_request(:get, "https://pub.dev/api/packages?page=2")
      .to_return({ status: 200, body: file_fixture('pub/packages?page=2') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 100
    assert_equal all_package_names.last, 'z_tools'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://pub.dev/api/packages?page=1")
      .to_return({ status: 200, body: file_fixture('pub/packages?page=1') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 100
    assert_equal recently_updated_package_names.last, 'serverpod'
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://pub.dev/api/packages/bloc")
      .to_return({ status: 200, body: file_fixture('pub/bloc') })
    package_metadata = @ecosystem.package_metadata('bloc')

    assert_equal package_metadata[:name], "bloc"
    assert_equal package_metadata[:description], "A predictable state management library that helps implement the BLoC (Business Logic Component) design pattern."
    assert_equal package_metadata[:homepage], "https://github.com/felangel/bloc"
    assert_nil package_metadata[:licenses]
    assert_equal package_metadata[:repository_url], "https://github.com/felangel/bloc"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://pub.dev/api/packages/bloc")
      .to_return({ status: 200, body: file_fixture('pub/bloc') })
    package_metadata = @ecosystem.package_metadata('bloc')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.first, {:number=>"0.1.0", :published_at=>"2018-10-08T02:30:26.298213Z"}
    assert_equal versions_metadata.last, {:number=>"8.0.3", :published_at=>"2022-02-28T16:43:11.890583Z"}
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://pub.dev/api/packages/bloc")
      .to_return({ status: 200, body: file_fixture('pub/bloc') })
    package_metadata = @ecosystem.package_metadata('bloc')
    dependencies_metadata = @ecosystem.dependencies_metadata('bloc', '8.0.3', package_metadata)
    
    assert_equal dependencies_metadata, [
      {:package_name=>"meta", :requirements=>"^1.3.0", :kind=>"runtime", :optional=>false, :ecosystem=>"Pub"},
      {:package_name=>"mocktail", :requirements=>"^0.2.0", :kind=>"Development", :optional=>false, :ecosystem=>"Pub"},
      {:package_name=>"stream_transform", :requirements=>"^2.0.0", :kind=>"Development", :optional=>false, :ecosystem=>"Pub"},
      {:package_name=>"test", :requirements=>"^1.18.2", :kind=>"Development", :optional=>false, :ecosystem=>"Pub"}
    ]
  end
end
