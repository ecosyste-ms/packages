require "test_helper"

class ElpaTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'elpa.nongnu.org', url: 'https://elpa.nongnu.org/nongnu', ecosystem: 'elpa')
    @ecosystem = Ecosystem::Elpa.new(@registry)
    @package = Package.new(ecosystem: 'elpa', name: 'ample-theme')
    @version = @package.versions.build(number: '0.3.0')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://elpa.nongnu.org/nongnu/ample-theme.html'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://elpa.nongnu.org/nongnu/ample-theme.html'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://elpa.nongnu.org/nongnu/ample-theme-0.3.0.tar'
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
    assert_equal install_command, 'M-x package-install RET ample-theme RET'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'M-x package-install RET ample-theme RET'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://elpa.nongnu.org/nongnu/ample-theme.html'
  end

  test 'all_package_names' do
    stub_request(:get, "https://elpa.nongnu.org/nongnu")
      .to_return({ status: 200, body: file_fixture('elpa/index.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 177
    assert_equal all_package_names.last, 'zig-mode'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://elpa.nongnu.org/nongnu")
      .to_return({ status: 200, body: file_fixture('elpa/index.html') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 177
    assert_equal recently_updated_package_names.last, 'zig-mode'
  end

  test 'package_metadata' do
    stub_request(:get, "https://elpa.nongnu.org/nongnu/ample-theme.html")
      .to_return({ status: 200, body: file_fixture('elpa/ample-theme.html') })
    package_metadata = @ecosystem.package_metadata('ample-theme')
    
    assert_equal package_metadata[:name], "ample-theme"
    assert_equal package_metadata[:description], "Calm Dark Theme for Emacs"
    assert_equal package_metadata[:homepage], "https://github.com/jordonbiondo/ample-theme"
    assert_nil package_metadata[:licenses]
    assert_equal package_metadata[:repository_url], "https://github.com/jordonbiondo/ample-theme"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://elpa.nongnu.org/nongnu/ample-theme.html")
      .to_return({ status: 200, body: file_fixture('elpa/ample-theme.html') })
    package_metadata = @ecosystem.package_metadata('ample-theme')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {
        :number=>"0.3.0", 
        :published_at=>"2021-Oct-22"
      }
    ]
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('ample-theme', '0.3.0', nil)

    assert_equal dependencies_metadata, []
  end
end
