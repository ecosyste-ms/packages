require "test_helper"

class CargoTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Crates.io', url: 'https://crates.io', ecosystem: 'Cargo')
    @ecosystem = Ecosystem::Cargo.new(@registry.url)
    @package = Package.new(ecosystem: 'Cargo', name: 'rand')
    @version = @package.versions.build(number: '0.8.5')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://crates.io/crates/rand/'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://crates.io/crates/rand/0.8.5'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://crates.io/api/v1/crates/rand/0.8.5/download'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, "https://docs.rs/rand/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, "https://docs.rs/rand/0.8.5"
  end

  test 'install_command' do
    package_url = @ecosystem.install_command(@package)
    assert_equal package_url, 'cargo install rand'
  end

  test 'install_command with version' do
    package_url = @ecosystem.install_command(@package, @version.number)
    assert_equal package_url, 'cargo install rand --version 0.8.5'
  end

  test 'check_status_url' do
    package_url = @ecosystem.check_status_url(@package)
    assert_equal package_url, "https://crates.io/api/v1/crates/rand"
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
end
