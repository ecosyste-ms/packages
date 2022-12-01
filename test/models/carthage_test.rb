require "test_helper"

class CarthageTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Carthage.io', url: 'https://carthage.io', ecosystem: 'carthage')
    @ecosystem = Ecosystem::Carthage.new(@registry)
    @package = @registry.packages.create(ecosystem: 'carthage', name: 'Carthage/ReactiveTask', repository_url: "https://github.com/Carthage/ReactiveTask")
    @version = @package.versions.create(number: '0.16.0', metadata: {download_url:"https://codeload.github.com/Carthage/ReactiveTask/tar.gz/refs/0.16.0"})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://github.com/Carthage/ReactiveTask"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, '0.16.0')
    assert_equal registry_url, "https://github.com/Carthage/ReactiveTask"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://codeload.github.com/Carthage/ReactiveTask/tar.gz/refs/0.16.0"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, '0.16.0')
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, '0.16.0')
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://github.com/Carthage/ReactiveTask"
  end

  test 'all_package_names' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/package_names/carthage")
      .to_return({ status: 200, body: file_fixture('carthage/carthage') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2368
    assert_equal all_package_names.last, 'zxingify/zxingify-objc'
  end

  test 'recently_updated_package_names' do
    # stub_request(:get, "https://github.com/SwiftPackageIndex/PackageList/commits/main.atom")
    # .to_return({ status: 200, body: file_fixture('carthage/main.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 0
    # assert_equal recently_updated_package_names.last, 'MediaPicker'
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/Carthage/ReactiveTask")
      .to_return({ status: 200, body: file_fixture('carthage/lookup?url=https:%2F%2Fgithub.com%2FCarthage%2FReactiveTask') })
    package_metadata = @ecosystem.package_metadata('Carthage/ReactiveTask')

    assert_equal package_metadata, {
      :name=>"Carthage/ReactiveTask",
      :description=>"Flexible, stream-based abstraction for launching processes",
      :repository_url=>"https://github.com/Carthage/ReactiveTask",
      :licenses=>"mit",
      :keywords_array=>["reactiveswift", "swift"],
      :homepage=>"",
      :tags_url=>"http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/Carthage%2FReactiveTask/tags",
      :namespace=>"Carthage"
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/Carthage%2FReactiveTask/tags")
      .to_return({ status: 200, body: file_fixture('carthage/tags') })
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/Carthage/ReactiveTask")
      .to_return({ status: 200, body: file_fixture('carthage/lookup?url=https:%2F%2Fgithub.com%2FCarthage%2FReactiveTask') })
    package_metadata = @ecosystem.package_metadata('Carthage/ReactiveTask')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.first, {:number=>"0.16.0", :published_at=>"2019-05-29T17:11:59.000Z", :metadata=>{:sha=>"df1bf7625684180b9377a8ba3c076db08d98757e", :download_url=>"https://codeload.github.com/Carthage/ReactiveTask/tar.gz/0.16.0"}}
  end
end
