require "test_helper"

class ElmTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'package.elm-lang.org', url: 'https://package.elm-lang.org', ecosystem: 'elm')
    @ecosystem = Ecosystem::Elm.new(@registry)
    @package = Package.new(ecosystem: 'elm', name: 'rtfeldman/count')
    @version = @package.versions.build(number: '1.0.1')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://package.elm-lang.org/packages/rtfeldman/count/latest'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://package.elm-lang.org/packages/rtfeldman/count/1.0.1'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://github.com/rtfeldman/count/archive/1.0.1.zip"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'elm-package install rtfeldman/count '
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'elm-package install rtfeldman/count 1.0.1'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://package.elm-lang.org/packages/rtfeldman/count/latest"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:elm/rtfeldman%2Fcount'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:elm/rtfeldman%2Fcount@1.0.1'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://package.elm-lang.org/all-packages")
      .to_return({ status: 200, body: file_fixture('elm/all-packages') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2473
    assert_equal all_package_names.last, 'zwilias/json-encode-exploration'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://package.elm-lang.org/all-packages/since/1")
      .to_return({ status: 200, body: file_fixture('elm/1') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 2473
    assert_equal recently_updated_package_names.first, 'lue-bird/elm-no-record-type-alias-constructor-function'
  end

  test 'package_metadata' do
    stub_request(:get, "https://package.elm-lang.org/packages/rtfeldman/count/releases.json")
      .to_return({ status: 200, body: file_fixture('elm/releases.json') })
    stub_request(:get, "https://package.elm-lang.org/packages/rtfeldman/count/1.0.1/elm.json")
      .to_return({ status: 200, body: file_fixture('elm/elm.json') })
    package_metadata = @ecosystem.package_metadata('rtfeldman/count')
    
    assert_equal package_metadata[:name], "rtfeldman/count"
    assert_equal package_metadata[:description], "Call record constructors with increasing integers. Useful for managing z-index."
    assert_nil package_metadata[:homepage]
    assert_equal package_metadata[:licenses], "BSD-3-Clause"
    assert_equal package_metadata[:repository_url], "https://github.com/rtfeldman/count"
    assert_nil package_metadata[:keywords_array]
    assert_equal package_metadata[:namespace], "rtfeldman"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://package.elm-lang.org/packages/rtfeldman/count/releases.json")
      .to_return({ status: 200, body: file_fixture('elm/releases.json') })
    stub_request(:get, "https://package.elm-lang.org/packages/rtfeldman/count/1.0.1/elm.json")
      .to_return({ status: 200, body: file_fixture('elm/elm.json') })
    package_metadata = @ecosystem.package_metadata('rtfeldman/count')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"1.0.0", :published_at=>"2017-04-15 16:24:16 +0100"},
      {:number=>"1.0.1", :published_at=>"2018-11-13 21:19:55 +0000"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://package.elm-lang.org/packages/rtfeldman/count/1.0.1/elm.json")
      .to_return({ status: 200, body: file_fixture('elm/elm.json') })
    dependencies_metadata = @ecosystem.dependencies_metadata('rtfeldman/count', '1.0.1', {})

    assert_equal dependencies_metadata, [
      {:package_name=>"elm/core", :requirements=>"1.0.0 <= v < 2.0.0", :kind=>"runtime", :ecosystem=>"elm"}
    ]
  end
end
