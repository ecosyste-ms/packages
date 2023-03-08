require "test_helper"

class HexTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Hex.pm', url: 'https://hex.pm', ecosystem: 'Hex')
    @ecosystem = Ecosystem::Hex.new(@registry)
    @package = Package.new(ecosystem: 'Hex', name: 'rand')
    @version = @package.versions.build(number: '0.8.5')
    @maintainer = @registry.maintainers.build(login: 'foo')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://hex.pm/packages/rand/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://hex.pm/packages/rand/0.8.5'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://repo.hex.pm/tarballs/rand-0.8.5.tar'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "http://hexdocs.pm/rand/"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, "http://hexdocs.pm/rand/0.8.5"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'mix hex.package fetch rand '
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'mix hex.package fetch rand 0.8.5'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://hex.pm/packages/rand/"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:hex/rand'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:hex/rand@0.8.5'
    assert PackageURL.parse(purl)
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

  test 'package_metadata' do
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy")
      .to_return({ status: 200, body: file_fixture('hex/phoenix_copy') })
    package_metadata = @ecosystem.package_metadata('phoenix_copy')
    
    assert_equal package_metadata[:name], "phoenix_copy"
    assert_equal package_metadata[:description], "Copy static assets for your Phoenix app during development and deployment."
    assert_nil package_metadata[:homepage]
    assert_equal package_metadata[:licenses], "MIT"
    assert_equal package_metadata[:repository_url], "https://github.com/aj-foster/phx_copy"
    assert_nil package_metadata[:keywords_array]
    assert_equal package_metadata[:downloads], 85
    assert_equal package_metadata[:downloads_period], "total"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy")
      .to_return({ status: 200, body: file_fixture('hex/phoenix_copy') })
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy/releases/0.1.1")
      .to_return({ status: 200, body: file_fixture('hex/0.1.1') })
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy/releases/0.1.0")
      .to_return({ status: 200, body: file_fixture('hex/0.1.0') })
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy/releases/0.1.0-rc.0")
      .to_return({ status: 200, body: file_fixture('hex/0.1.0-rc.0') })
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy/releases/0.1.0-rc.1")
      .to_return({ status: 200, body: file_fixture('hex/0.1.0-rc.1') })
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy/releases/0.1.0-rc.2")
      .to_return({ status: 200, body: file_fixture('hex/0.1.0-rc.2') })
    package_metadata = @ecosystem.package_metadata('phoenix_copy')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.1.1", :published_at=>"2022-07-08T03:08:58.458116Z", :integrity=>"sha256-38ce387d834a1f54e86be27e877938fa28cb8e33211666051508c82358e1ef21", :metadata=>{:downloads=>58}},
      {:number=>"0.1.0-rc.2", :published_at=>"2022-03-25T02:02:53.226729Z", :integrity=>"sha256-91de7623289bc7f0fd9f015c46cae101fd760d7489def29cb88a63c9dc9b3736", :metadata=>{:downloads=>6}},
      {:number=>"0.1.0-rc.1", :published_at=>"2022-03-23T01:30:45.366912Z", :integrity=>"sha256-e9dee9d7a45d193a17ba324b0a1d74be153e15ed1d05144a883884bbfc76e240", :metadata=>{:downloads=>nil}},
      {:number=>"0.1.0-rc.0", :published_at=>"2022-03-23T01:13:50.946007Z", :integrity=>"sha256-feed6ef902fe8d9bf937c39261142be0aee8db84f2c12e49ed471bec2e35ac97", :metadata=>{:downloads=>nil}},
      {:number=>"0.1.0", :published_at=>"2022-03-25T02:22:52.658502Z", :integrity=>"sha256-e2a8663260e1e6334b98160a8dafdd09d520e5955b12d4363b5e0231f7aa0a0b", :metadata=>{:downloads=>nil}},
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://hex.pm/api/packages/phoenix_copy/releases/0.1.0")
      .to_return({ status: 200, body: file_fixture('hex/0.1.0') })
    dependencies_metadata = @ecosystem.dependencies_metadata('phoenix_copy', '0.1.0', nil)

    assert_equal dependencies_metadata, [
      {:package_name=>"file_system", :requirements=>"~> 0.2", :kind=>"runtime", :optional=>false, :ecosystem=>"hex"}
    ]
  end

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://hex.pm/users/foo'
  end
end
