require "test_helper"

class CondaTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Conda.org', url: 'https://anaconda.org/anaconda', ecosystem: 'conda', metadata: {'kind' => 'anaconda', 'key' => 'Main', 'api' => 'https://repo.ananconda.com'})
    @ecosystem = Ecosystem::Conda.new(@registry)
    @package = Package.new(ecosystem: 'conda', name: 'aiofiles')
    @version = @package.versions.build(number: '22.1.0', metadata: {'download_url' => 'https://anaconda.org/anaconda/aiofiles/22.1.0/download/linux-64/aiofiles-22.1.0-py_0.tar.bz2'})
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://anaconda.org/anaconda/aiofiles'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://anaconda.org/anaconda/aiofiles'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, "https://anaconda.org/anaconda/aiofiles/22.1.0/download/linux-64/aiofiles-22.1.0-py_0.tar.bz2"
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
    assert_equal install_command, 'conda install -c anaconda aiofiles'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'conda install -c anaconda aiofiles=22.1.0'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://conda.libraries.io/package/aiofiles"
  end

  test 'all_package_names' do
    stub_request(:get, "https://conda.libraries.io/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2843
    assert_equal all_package_names.last, 'zlib-devel-amzn2-aarch64'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://conda.libraries.io/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 1
    assert_equal recently_updated_package_names.last, 'pyreadline3'
  end
  
  test 'package_metadata' do
    stub_request(:get, "https://conda.libraries.io/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    package_metadata = @ecosystem.package_metadata('aiofiles')

    assert_equal package_metadata[:name], "aiofiles"
    assert_nil package_metadata[:description], "aiofiles"
    assert_equal package_metadata[:homepage], "https://github.com/Tinche/aiofiles"
    assert_equal package_metadata[:licenses], "Apache 2.0"
    assert_equal package_metadata[:repository_url], "https://github.com/Tinche/aiofiles"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://conda.libraries.io/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    package_metadata = @ecosystem.package_metadata('aiofiles')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.first, {:number=>"0.3.2", :published_at=>"2018-04-03 19:04:57 +0000", :licenses=>"Apache 2.0", :metadata=>{:arch=>"linux-32", :download_url=>"https://repo.anaconda.com/pkgs/main/linux-32/aiofiles-0.3.2-py35_0.tar.bz2"}}
    assert_equal versions_metadata.second, {:number=>"0.4.0", :published_at=>"2018-08-28 02:13:51 +0000", :licenses=>"Apache 2.0", :metadata=>{:arch=>"linux-32", :download_url=>"https://repo.anaconda.com/pkgs/main/linux-32/aiofiles-0.4.0-py35_0.tar.bz2"}}
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://conda.libraries.io/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    package_metadata = @ecosystem.package_metadata('aiofiles')
    dependencies_metadata = @ecosystem.dependencies_metadata('aiofiles', '0.4.0', package_metadata)
    
    assert_equal dependencies_metadata, [{:package_name=>"python", :requirements=>">=3.5,<3.6.0a0", :kind=>"runtime", :ecosystem=>"conda"}]
  end
end
