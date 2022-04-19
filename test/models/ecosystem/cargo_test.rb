require "test_helper"

class CargoTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Crates.io', url: 'https://crates.io', ecosystem: 'Cargo')
    @ecosystem = Ecosystem::Cargo.new(@registry.url)
    @package = Package.new(ecosystem: 'Cargo', name: 'rand')
    @version = @package.versions.build(number: '0.8.5')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://crates.io/crates/rand/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version.number)
    assert_equal registry_url, 'https://crates.io/crates/rand/0.8.5'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://crates.io/api/v1/crates/rand/0.8.5/download'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://docs.rs/rand/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "https://docs.rs/rand/0.8.5"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'cargo install rand'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'cargo install rand --version 0.8.5'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://crates.io/api/v1/crates/rand"
  end

  test 'all_package_names' do
    stub_request(:get, "https://crates.io/api/v1/crates?page=1&per_page=100")
      .to_return({ status: 200, body: file_fixture('cargo/crates') })
      stub_request(:get, "https://crates.io/api/v1/crates?page=2&per_page=100")
      .to_return({ status: 200, body: file_fixture('cargo/crates2') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 100
    assert_equal all_package_names.last, 'aba-cache'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://crates.io/api/v1/summary")
      .to_return({ status: 200, body: file_fixture('cargo/summary') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 20
    assert_equal recently_updated_package_names.last, 'findsrouce'
  end

  test 'package_metadata' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib")
      .to_return({ status: 200, body: file_fixture('cargo/parameters_lib') })
    package_metadata = @ecosystem.package_metadata('parameters_lib')
    
    assert_equal package_metadata[:name], "parameters_lib"
    assert_equal package_metadata[:description], "Library"
    assert_equal package_metadata[:homepage], "https://github.com/TheFox/parameters-rust"
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/TheFox/parameters-rust"
    assert_equal package_metadata[:keywords_array], ["env", "variables"]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib")
      .to_return({ status: 200, body: file_fixture('cargo/parameters_lib') })
    package_metadata = @ecosystem.package_metadata('parameters_lib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.1.0", :published_at=>"2022-03-24T16:19:57.595451+00:00"},
      {:number=>"0.1.0-dev.2", :published_at=>"2022-03-24T16:08:54.337646+00:00"},
      {:number=>"0.1.0-dev.1", :published_at=>"2022-03-24T15:58:36.858899+00:00"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://crates.io/api/v1/crates/parameters_lib/0.1.0/dependencies")
      .to_return({ status: 200, body: file_fixture('cargo/dependencies') })
    dependencies_metadata = @ecosystem.dependencies_metadata('parameters_lib', '0.1.0', nil)
    
    assert_equal dependencies_metadata, [{:package_name=>"regex", :requirements=>"^1.5.0", :kind=>"normal", :optional=>false, :ecosystem=>"cargo"}]
  end
end
