require "test_helper"

class CondaTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Conda.org', url: 'https://anaconda.org/anaconda', ecosystem: 'conda', metadata: {'kind' => 'anaconda', 'key' => 'Main', 'api' => 'https://repo.ananconda.com'})
    @registry2 = Registry.new(name: 'conda-forge.org', url: 'https://conda-forge.org/', ecosystem: 'conda', metadata: {'kind' => 'conda-forge', 'key' => 'CondaForge', 'api' => 'https://conda.anaconda.org'})
    @ecosystem = Ecosystem::Conda.new(@registry)
    @ecosystem2 = Ecosystem::Conda.new(@registry2)
    @package = Package.new(ecosystem: 'conda', name: 'aiofiles')
    @package2 = @registry2.packages.build(ecosystem: 'conda', name: 'aiofiles')
    @version = @package.versions.build(number: '22.1.0', metadata: {'download_url' => 'https://anaconda.org/anaconda/aiofiles/22.1.0/download/linux-64/aiofiles-22.1.0-py_0.tar.bz2'})
    @version2 = @package2.versions.build(number: '22.1.0', metadata: {'download_url' => 'https://anaconda.org/conda-forge/aiofiles/22.1.0/download/linux-64/aiofiles-22.1.0-py_0.tar.bz2'})
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
    assert_equal check_status_url, "https://anaconda.org/anaconda/aiofiles"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:conda/aiofiles'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:conda/aiofiles@22.1.0'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://conda.ecosyste.ms/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 2843
    assert_equal all_package_names.last, 'zlib-devel-amzn2-aarch64'
  end

  test 'package_metadata' do
    stub_request(:get, "https://conda.ecosyste.ms/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    package_metadata = @ecosystem.package_metadata('aiofiles')

    assert_equal package_metadata[:name], "aiofiles"
    assert_nil package_metadata[:description], "aiofiles"
    assert_equal package_metadata[:homepage], "https://github.com/Tinche/aiofiles"
    assert_equal package_metadata[:licenses], "Apache 2.0"
    assert_equal package_metadata[:repository_url], "https://github.com/Tinche/aiofiles"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://conda.ecosyste.ms/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    package_metadata = @ecosystem.package_metadata('aiofiles')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata.first, {:number=>"0.3.2", :published_at=>"2018-04-03 19:04:57 +0000", :licenses=>"Apache 2.0", :metadata=>{:arch=>"linux-32", :download_url=>"https://repo.anaconda.com/pkgs/main/linux-32/aiofiles-0.3.2-py35_0.tar.bz2"}}
    assert_equal versions_metadata.second, {:number=>"0.4.0", :published_at=>"2018-08-28 02:13:51 +0000", :licenses=>"Apache 2.0", :metadata=>{:arch=>"linux-32", :download_url=>"https://repo.anaconda.com/pkgs/main/linux-32/aiofiles-0.4.0-py35_0.tar.bz2"}}
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://conda.ecosyste.ms/Main/")
      .to_return({ status: 200, body: file_fixture('conda/index.html') })
    package_metadata = @ecosystem.package_metadata('aiofiles')
    dependencies_metadata = @ecosystem.dependencies_metadata('aiofiles', '0.4.0', package_metadata)
    
    assert_equal dependencies_metadata, [{:package_name=>"python", :requirements=>">=3.5,<3.6.0a0", :kind=>"runtime", :ecosystem=>"conda"}]
  end

  test 'conda-forge registry_url' do
    registry_url = @ecosystem2.registry_url(@package2)
    assert_equal registry_url, 'https://anaconda.org/conda-forge/aiofiles'
  end

  test 'conda-forge registry_url with version' do
    registry_url = @ecosystem2.registry_url(@package2, @version2)
    assert_equal registry_url, 'https://anaconda.org/conda-forge/aiofiles'
  end

  test 'conda-forge download_url' do
    download_url = @ecosystem2.download_url(@package2, @version2)
    assert_equal download_url, "https://anaconda.org/conda-forge/aiofiles/22.1.0/download/linux-64/aiofiles-22.1.0-py_0.tar.bz2"
  end

  test 'conda-forge documentation_url' do
    documentation_url = @ecosystem2.documentation_url(@package2)
    assert_nil documentation_url
  end

  test 'conda-forge documentation_url with version' do
    documentation_url = @ecosystem2.documentation_url(@package2, @version2.number)
    assert_nil documentation_url
  end

  test 'conda-forge install_command' do
    install_command = @ecosystem2.install_command(@package2)
    assert_equal install_command, 'conda install -c conda-forge aiofiles'
  end

  test 'conda-forge install_command with version' do
    install_command = @ecosystem2.install_command(@package2, @version2.number)
    assert_equal install_command, 'conda install -c conda-forge aiofiles=22.1.0'
  end

  test 'conda-forge check_status_url' do
    check_status_url = @ecosystem2.check_status_url(@package2)
    assert_equal check_status_url, "https://anaconda.org/conda-forge/aiofiles"
  end
end
