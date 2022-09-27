require "test_helper"

class PypiTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    @ecosystem = Ecosystem::Pypi.new(@registry.url)
    @package = Package.new(ecosystem: 'pypi', name: 'urllib3')
    @version = @package.versions.build(number: '1.26.8', metadata: {download_url: 'https://files.pythonhosted.org/packages/8b/e1/40122572f57349365391b8955178d52cd42d2c1f767030cbd196883adee7/yiban-0.1.2.32-py3-none-any.whl'})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://pypi.org/project/urllib3/'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://pypi.org/project/urllib3/1.26.8'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://files.pythonhosted.org/packages/8b/e1/40122572f57349365391b8955178d52cd42d2c1f767030cbd196883adee7/yiban-0.1.2.32-py3-none-any.whl'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://urllib3.readthedocs.io/'
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, 'https://urllib3.readthedocs.io/en/1.26.8'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'pip install urllib3 --index-url https://pypi.org/simple'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'pip install urllib3==1.26.8 --index-url https://pypi.org/simple'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://pypi.org/project/urllib3/"
  end

  test 'all_package_names' do
    stub_request(:get, "https://pypi.org/simple/")
      .to_return({ status: 200, body: file_fixture('pypi/index.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 364372
    assert_equal all_package_names.last, 'zzzZZZzzz'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://pypi.org/rss/updates.xml")
      .to_return({ status: 200, body: file_fixture('pypi/updates.xml') })
    stub_request(:get, "https://pypi.org/rss/packages.xml")
    .to_return({ status: 200, body: file_fixture('pypi/packages.xml') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 114
    assert_equal recently_updated_package_names.last, 'Lgy'
  end

  test 'package_metadata' do
    stub_request(:get, "https://pypi.org/pypi/yiban/json")
      .to_return({ status: 200, body: file_fixture('pypi/yiban') })
    stub_request(:get, "https://pypistats.org/api/packages/yiban/recent")
      .to_return({ status: 200, body: file_fixture('pypi/recent') })
    package_metadata = @ecosystem.package_metadata('yiban')
    
    assert_equal package_metadata[:name], "yiban"
    assert_equal package_metadata[:description], "Yiban Api"
    assert_equal package_metadata[:homepage], "https://github.com/DukeBode/Yiban"
    assert_equal package_metadata[:licenses], "BSD 3-Clause"
    assert_equal package_metadata[:repository_url], "https://github.com/DukeBode/Yiban"
    assert_equal package_metadata[:keywords_array], ["Yiban"]
    assert_equal package_metadata[:downloads], 18
    assert_equal package_metadata[:downloads_period], "last-month"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://pypi.org/pypi/yiban/json")
      .to_return({ status: 200, body: file_fixture('pypi/yiban') })
    stub_request(:get, "https://pypistats.org/api/packages/yiban/recent")
      .to_return({ status: 200, body: file_fixture('pypi/recent') })
    package_metadata = @ecosystem.package_metadata('yiban')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {
        :number=>"0.1.2.32", 
        :published_at=>"2019-11-05T15:06:04", 
        :integrity=>"sha256-29ffb8f9b1d6114757a53a1a713a4e07ce4e1c4c50d31332644593db208f30e7", 
        :metadata=>{
          :download_url=>"https://files.pythonhosted.org/packages/8b/e1/40122572f57349365391b8955178d52cd42d2c1f767030cbd196883adee7/yiban-0.1.2.32-py3-none-any.whl"
        }
      }
    ]
  end

  test 'dependencies_metadata' do
    dependencies_metadata = @ecosystem.dependencies_metadata('yiban', '0.1.2.32', nil)

    assert_equal dependencies_metadata, []
  end
end
