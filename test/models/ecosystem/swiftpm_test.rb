require "test_helper"

class SwiftpmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Swiftpm.io', url: 'https://swiftpm.io', ecosystem: 'swiftpm')
    @ecosystem = Ecosystem::Swiftpm.new(@registry)
    @package = @registry.packages.create(ecosystem: 'swiftpm', name: 'github.com/swift-cloud/Compute', repository_url: "https://github.com/swift-cloud/Compute")
    @version = @package.versions.create(number: '2.3.1', metadata: {download_url:"https://codeload.github.com/swift-cloud/Compute/tar.gz/refs/2.3.1"})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "https://swiftpackageindex.com/swift-cloud/Compute"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, '2.3.1')
    assert_equal registry_url, "https://swiftpackageindex.com/swift-cloud/Compute"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://codeload.github.com/swift-cloud/Compute/tar.gz/refs/2.3.1"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://swiftpackageindex.com/swift-cloud/Compute/documentation"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, '2.3.1')
    assert_equal documentation_url, "https://swiftpackageindex.com/swift-cloud/Compute/2.3.1/documentation"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, '2.3.1')
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://github.com/swift-cloud/Compute"
  end

  test 'all_package_names' do
    stub_request(:get, "https://raw.githubusercontent.com/SwiftPackageIndex/PackageList/main/packages.json")
      .to_return({ status: 200, body: file_fixture('swiftpm/packages.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 5200
    assert_equal all_package_names.last, 'github.com/zxcj04/WMSKit'
  end

  test 'recently_updated_package_names' do
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 0
    assert_nil recently_updated_package_names.last
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/swift-cloud/Compute")
      .to_return({ status: 200, body: file_fixture('swiftpm/lookup?url=https:%2F%2Fgithub.com%2Fswift-cloud%2FCompute') })
    package_metadata = @ecosystem.package_metadata('github.com/swift-cloud/Compute')

    assert_equal package_metadata, {
      :name=>"github.com/swift-cloud/Compute",
      :repository_url=>"https://github.com/swift-cloud/Compute",
      :licenses=>"mpl-2.0", :keywords_array=>["fastly", "swift", "wasm"],
      :homepage=>"https://compute-runtime.swift.cloud/documentation/compute/",
      :description=>"Swift runtime for Fastly Compute@Edge",
      :tags_url=>"http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/swift-cloud%2FCompute/tags"
    }
  end

  test 'versions_metadata' do
    stub_request(:get, "http://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/swift-cloud%2FCompute/tags")
      .to_return({ status: 200, body: file_fixture('swiftpm/tags') })
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/swift-cloud/Compute")
      .to_return({ status: 200, body: file_fixture('swiftpm/lookup?url=https:%2F%2Fgithub.com%2Fswift-cloud%2FCompute') })
    package_metadata = @ecosystem.package_metadata('github.com/swift-cloud/Compute')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata,[
      {:number=>"1.9.0", :published_at=>"2022-09-15T23:22:30.000Z", :metadata=>{:sha=>"5d1ee1bdb729d228184dbd1b29f2e1bc202b089b", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.9.0"}},
      {:number=>"1.8.0", :published_at=>"2022-08-22T18:11:24.000Z", :metadata=>{:sha=>"644a3468520aae854287dd1da0e99e8ebb667324", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.8.0"}},
      {:number=>"1.7.0", :published_at=>"2022-06-29T20:00:58.000Z", :metadata=>{:sha=>"6ad4ec6af8601e565c9e339d3565c987ae8fed78", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.7.0"}},
      {:number=>"1.6.0", :published_at=>"2022-05-31T20:12:08.000Z", :metadata=>{:sha=>"c265ebb0baa216b3bf0b52b55e08affd8e09d537", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.6.0"}},
      {:number=>"1.5.1", :published_at=>"2022-05-30T21:05:23.000Z", :metadata=>{:sha=>"cc7ce1f49d95bc1c12da23e433f1b927e51ad8f1", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.5.1"}},
      {:number=>"1.5.0", :published_at=>"2022-05-30T16:24:23.000Z", :metadata=>{:sha=>"a013ba49e8e4cbc7d304bc53c7d1cdc057b756c8", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.5.0"}},
      {:number=>"1.4.0", :published_at=>"2022-05-26T18:58:12.000Z", :metadata=>{:sha=>"b32b9b2f8d4d9995e2bdffa7166f8f552e2bb293", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.4.0"}},
      {:number=>"1.3.0", :published_at=>"2022-04-14T23:07:08.000Z", :metadata=>{:sha=>"8c84156b144fc44ce758ea7745f9d0c902520904", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.3.0"}},
      {:number=>"1.2.0", :published_at=>"2022-04-02T18:24:40.000Z", :metadata=>{:sha=>"a4d79828f24c9279a0be62c754cb7fb7a2394782", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.2.0"}},
      {:number=>"1.1.0", :published_at=>"2022-03-26T21:23:15.000Z", :metadata=>{:sha=>"ea566c75bd5585b3ed133497785fef343b9ce003", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.1.0"}},
      {:number=>"1.0.0", :published_at=>"2022-03-08T14:01:37.000Z", :metadata=>{:sha=>"79487d21b093e7013451c6341f5dce38aa8cac23", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.0.0"}},
      {:number=>"2.0.0", :published_at=>"2022-11-27T19:56:02.000Z", :metadata=>{:sha=>"4a711919bb69f548816256d12e4f77f564ab7539", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/2.0.0"}},
      {:number=>"1.11.0", :published_at=>"2022-11-26T23:40:38.000Z", :metadata=>{:sha=>"1b8323caa0e44c87e426b3f414742ea3ab5ce343", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.11.0"}},
      {:number=>"1.10.0", :published_at=>"2022-11-24T16:41:01.000Z", :metadata=>{:sha=>"45032b1c3b6f3b1ee7d201aa0b37b872efa70944", :download_url=>"https://codeload.github.com/swift-cloud/Compute/tar.gz/1.10.0"}}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https://github.com/swift-cloud/Compute")
      .to_return({ status: 200, body: file_fixture('swiftpm/lookup?url=https:%2F%2Fgithub.com%2Fswift-cloud%2FCompute') })
    stub_request(:get, "https://raw.githubusercontent.com/swift-cloud/Compute/1.11.0/Package.resolved")
      .to_return({ status: 200, body: file_fixture('swiftpm/Package.resolved') })
    package_metadata = @ecosystem.package_metadata('github.com/swift-cloud/Compute')
    dependencies_metadata = @ecosystem.dependencies_metadata('github.com/swift-cloud/Compute', '1.11.0', package_metadata)
    
    assert_equal dependencies_metadata, [
      {:package_name=>"github.com/krzyzanowskim/CryptoSwift", :requirements=>"1.6.0", :kind=>"runtime", :ecosystem=>"swiftpm"},
      {:package_name=>"github.com/apple/swift-docc-plugin", :requirements=>"1.0.0", :kind=>"runtime", :ecosystem=>"swiftpm"}
    ]
  end
end
