require "test_helper"

class HexTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Hex.pm', url: 'https://hex.pm', ecosystem: 'Hex')
    @ecosystem = Ecosystem::Hex.new(@registry.url)
    @package = Package.new(ecosystem: 'Hex', name: 'rand')
    @version = @package.versions.build(number: '0.8.5')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://hex.pm/packages/rand/'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://hex.pm/packages/rand/0.8.5'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://repo.hex.pm/tarballs/rand-0.8.5.tar'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, "http://hexdocs.pm/rand/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, "http://hexdocs.pm/rand/0.8.5"
  end

  test 'install_command' do
    package_url = @ecosystem.install_command(@package)
    assert_equal package_url, 'mix hex.package fetch rand '
  end

  test 'install_command with version' do
    package_url = @ecosystem.install_command(@package, @version.number)
    assert_equal package_url, 'mix hex.package fetch rand 0.8.5'
  end

  test 'check_status_url' do
    package_url = @ecosystem.check_status_url(@package)
    assert_equal package_url, "https://hex.pm/packages/rand/"
  end

  test 'all_package_names' do
    stub_request(:get, "https://hex.pm/api/packages?page=1")
      .to_return({ status: 200, body: file_fixture('hex/packages-1') })
      stub_request(:get, "https://hex.pm/api/packages?page=2")
      .to_return({ status: 200, body: file_fixture('hex/packages-2') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 100
    assert_equal all_package_names.last, 'admin_elf'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://hex.pm/api/packages?sort=inserted_at")
      .to_return({ status: 200, body: file_fixture('hex/new-packages') })
    stub_request(:get, "https://hex.pm/api/packages?sort=updated_at")
      .to_return({ status: 200, body: file_fixture('hex/updated-packages') })
    
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 185
    assert_equal recently_updated_package_names.last, 'stellar_base'
  end
end
