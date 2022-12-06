require "test_helper"

class RacketTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Racket', url: 'http://pkgs.racket-lang.org', ecosystem: 'racket')
    @ecosystem = Ecosystem::Racket.new(@registry)
    @package = @registry.packages.create(ecosystem: 'racket', name: '4chdl', repository_url: "https://github.com/winny-/4chdl")
    @version = @package.versions.create(number: '1.0.0', :metadata=>{:download_url=>"https://codeload.github.com/winny-/4chdl/tar.gz/refs/heads/master"})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, "http://pkgs.racket-lang.org/package/4chdl"
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, '1.0.0')
    assert_equal registry_url, "http://pkgs.racket-lang.org/package/4chdl"
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, nil)
    assert_equal download_url, "https://codeload.github.com/winny-/4chdl/tar.gz/refs/heads/master"
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, "https://docs.racket-lang.org/4chdl/index.html"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, '1.0.0')
    assert_equal documentation_url, "https://docs.racket-lang.org/4chdl/index.html"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'raco pkg install 4chdl'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, '1.0.0')
    assert_equal install_command, 'raco pkg install 4chdl'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "http://pkgs.racket-lang.org/package/4chdl"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:racket/4chdl'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:racket/4chdl@1.0.0'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://pkgs.racket-lang.org/pkgs-all.json.gz")
      .to_return({ status: 200, body: file_fixture('racket/pkgs-all.json.gz') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2132
    assert_equal all_package_names.last, 'zuo-doc'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://pkgs.racket-lang.org/pkgs-all.json.gz")
      .to_return({ status: 200, body: file_fixture('racket/pkgs-all.json.gz') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 100
    assert_equal recently_updated_package_names.last, 'distro-build-test'
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://pkgs.racket-lang.org/pkgs-all.json.gz")
      .to_return({ status: 200, body: file_fixture('racket/pkgs-all.json.gz') })
    package_metadata = @ecosystem.package_metadata('4chdl')

    assert_equal package_metadata, {
      :name=>"4chdl", 
      :repository_url=>"https://github.com/winny-/4chdl", 
      :description=>"4chan image downloader and library to interact with the JSON API.", 
      :keywords_array=>["4chan", "api", "client", "http"]
    }
  end

  test 'versions_metadata' do
    versions_metadata = @ecosystem.versions_metadata({name: '4chdl'})

    assert_equal versions_metadata, []
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('4chdl', '0.3.0', nil)
    
    assert_equal dependencies_metadata, []
  end
end
