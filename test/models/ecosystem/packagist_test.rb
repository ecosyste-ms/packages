require "test_helper"

class PackagistTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Packagist.org', url: 'https://packagist.org', ecosystem: 'Packagist')
    @ecosystem = Ecosystem::Packagist.new(@registry.url)
    @package = Package.new(ecosystem: 'Packagist', name: 'psr/log')
    @version = @package.versions.build(number: '3.0.0')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://packagist.org/packages/psr/log#'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://packagist.org/packages/psr/log#3.0.0'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'composer require psr/log'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'composer require psr/log:3.0.0'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://packagist.org/packages/psr/log#"
  end

  test 'all_package_names' do
    stub_request(:get, "https://packagist.org/packages/list.json")
      .to_return({ status: 200, body: file_fixture('packagist/list.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 331163
    assert_equal all_package_names.last, 'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz/no-trailing-comma'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://packagist.org/feeds/releases.rss")
      .to_return({ status: 200, body: file_fixture('packagist/releases.rss') })
    stub_request(:get, "https://packagist.org/feeds/packages.rss")
    .to_return({ status: 200, body: file_fixture('packagist/packages.rss') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 75
    assert_equal recently_updated_package_names.last, 'pringuin/pimcore-lucene-search'
  end

  test 'fetch_package_metadata' do
    skip("To be implemented")
  end

  test 'map_package_metadata' do
    skip("To be implemented")
  end

  test 'versions_metadata' do
    skip("To be implemented")
  end

  test 'dependencies_metadata' do
    skip("To be implemented")
  end
end
