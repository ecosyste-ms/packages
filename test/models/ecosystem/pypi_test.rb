require "test_helper"

class PypiTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    @ecosystem = Ecosystem::Pypi.new(@registry)
    @package = Package.new(ecosystem: 'pypi', name: 'urllib3')
    @version = @package.versions.build(number: '1.26.8', metadata: {download_url: 'https://files.pythonhosted.org/packages/8b/e1/40122572f57349365391b8955178d52cd42d2c1f767030cbd196883adee7/yiban-0.1.2.32-py3-none-any.whl'})
    @maintainer = @registry.maintainers.build(login: 'foo')
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

  test 'documentation_url with metadata' do
    @package.metadata['documentation'] = 'https://docs.urllib3.com'
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_equal documentation_url, 'https://docs.urllib3.com'
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

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:pypi/urllib3'
    assert PackageURL.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:pypi/urllib3@1.26.8'
    assert PackageURL.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://pypi.org/simple/")
      .to_return({ status: 200, body: file_fixture('pypi/index.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 364372
    assert_equal all_package_names.last, 'zzzzzzzzz'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://pypi.org/rss/updates.xml")
      .to_return({ status: 200, body: file_fixture('pypi/updates.xml') })
    stub_request(:get, "https://pypi.org/rss/packages.xml")
    .to_return({ status: 200, body: file_fixture('pypi/packages.xml') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 114
    assert_equal recently_updated_package_names.last, 'lgy'
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
    assert_equal package_metadata[:metadata], {"funding"=>nil, "documentation" => "https://dukebode.github.io/Yiban", "classifiers"=>["Development Status :: 1 - Planning", "Intended Audience :: Developers", "Intended Audience :: Education", "License :: OSI Approved :: BSD License", "Natural Language :: Chinese (Simplified)", "Operating System :: Microsoft :: Windows :: Windows 10", "Programming Language :: Python :: 3.8", "Programming Language :: Python :: Implementation :: PyPy"], "normalized_name"=>"yiban"}
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
          :download_url=>"https://files.pythonhosted.org/packages/8b/e1/40122572f57349365391b8955178d52cd42d2c1f767030cbd196883adee7/yiban-0.1.2.32-py3-none-any.whl",
          :requires_python=>">=3.8",
          :yanked=>false,
          :yanked_reason=>nil,
          :packagetype=>"bdist_wheel",
          :python_version=>"py3",
          :size=>8856,
          :has_sig=>false
        }
      }
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://pypi.org/pypi/yiban/0.1.2.32/json")
      .to_return({ status: 200, body: file_fixture('pypi/yiban-0.1.2.32-json') })
    
    dependencies_metadata = @ecosystem.dependencies_metadata('yiban', '0.1.2.32', nil)

    assert_equal dependencies_metadata, [{:package_name=>"openpyxl", :requirements=>"*", :kind=>"runtime", :optional=>false, :ecosystem=>"pypi"}]
  end

  test 'dependencies_metadata with kinds' do
    stub_request(:get, "https://pypi.org/pypi/siuba/0.3.0/json")
      .to_return({ status: 200, body: file_fixture('pypi/siuba-0.3.0-json') })
    
    dependencies_metadata = @ecosystem.dependencies_metadata('siuba', '0.3.0', nil)

    assert_equal dependencies_metadata, [
      {:package_name=>"hypothesis", :requirements=>"*", :kind=>"extra == 'test'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"pytest", :requirements=>"*", :kind=>"extra == 'test'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"gapminder", :requirements=>"==0.1", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"jupytext", :requirements=>"*", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"nbsphinx", :requirements=>"*", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"sphinx", :requirements=>"*", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"nbval", :requirements=>"*", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"jupyter", :requirements=>"*", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"plotnine", :requirements=>"*", :kind=>"extra == 'docs'", :optional=>true, :ecosystem=>"pypi"},
      {:package_name=>"PyYAML", :requirements=>">=3.0.0", :kind=>"runtime", :optional=>false, :ecosystem=>"pypi"},
      {:package_name=>"SQLAlchemy", :requirements=>">=1.2.19", :kind=>"runtime", :optional=>false, :ecosystem=>"pypi"},
      {:package_name=>"numpy", :requirements=>">=1.12.0", :kind=>"runtime", :optional=>false, :ecosystem=>"pypi"},
      {:package_name=>"pandas", :requirements=>">=0.24.0", :kind=>"runtime", :optional=>false, :ecosystem=>"pypi"}
    ]
  end

  test 'maintainer_url' do 
    assert_equal @ecosystem.maintainer_url(@maintainer), 'https://pypi.org/user/foo/'
  end

  test 'parse_repository_url' do
    description = JSON.parse file_fixture('pypi/yiban').read
    assert_equal @ecosystem.parse_repository_url(description), 'https://github.com/DukeBode/Yiban'
  end

  test 'parse_repository_url prefer package name match' do
    description = JSON.parse file_fixture('pypi/easybuild-easyconfigs-json').read
    assert_equal @ecosystem.parse_repository_url(description), 'https://github.com/easybuilders/easybuild-easyconfigs'
  end

  test 'versions_metadata includes python requirements and pypi specific fields' do
    stub_request(:get, "https://pypi.org/pypi/yiban/json")
      .to_return({ status: 200, body: file_fixture('pypi/yiban') })
    stub_request(:get, "https://pypistats.org/api/packages/yiban/recent")
      .to_return({ status: 200, body: file_fixture('pypi/recent') })
    package_metadata = @ecosystem.package_metadata('yiban')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)
    
    first_version = versions_metadata.first
    assert_equal first_version[:metadata][:requires_python], ">=3.8"
    assert_equal first_version[:metadata][:yanked], false
    assert_nil first_version[:metadata][:yanked_reason]
    assert_equal first_version[:metadata][:packagetype], "bdist_wheel"
    assert_equal first_version[:metadata][:python_version], "py3"
    assert_equal first_version[:metadata][:size], 8856
    assert_equal first_version[:metadata][:has_sig], false
  end
end
