require "test_helper"

class PypiTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
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
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:pypi/urllib3@1.26.8'
    assert Purl.parse(purl)
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
    assert_equal package_metadata[:metadata], {"funding"=>nil, "documentation" => "https://dukebode.github.io/Yiban", "classifiers"=>["Development Status :: 1 - Planning", "Intended Audience :: Developers", "Intended Audience :: Education", "License :: OSI Approved :: BSD License", "Natural Language :: Chinese (Simplified)", "Operating System :: Microsoft :: Windows :: Windows 10", "Programming Language :: Python :: 3.8", "Programming Language :: Python :: Implementation :: PyPy"], "normalized_name"=>"yiban", "project_status"=>{"status"=>"active"}}
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

  test 'package_metadata includes project status when available' do
    package_json = JSON.parse(file_fixture('pypi/yiban').read)
    package_json['project-status'] = { 'status' => 'archived', 'reason' => 'No longer maintained' }
    
    stub_request(:get, "https://pypi.org/pypi/yiban/json")
      .to_return({ status: 200, body: package_json.to_json })
    stub_request(:get, "https://pypistats.org/api/packages/yiban/recent")
      .to_return({ status: 200, body: file_fixture('pypi/recent') })
    
    package_metadata = @ecosystem.package_metadata('yiban')
    
    assert_equal package_metadata[:metadata]['project_status'], {'status' => 'archived', 'reason' => 'No longer maintained'}
  end

  test 'check_status returns project status from API' do
    package_json = JSON.parse(file_fixture('pypi/yiban').read)
    package_json['project-status'] = { 'status' => 'archived' }
    
    stub_request(:get, "https://pypi.org/project/urllib3/")
      .to_return({ status: 200, body: '' })
    stub_request(:get, "https://pypi.org/pypi/urllib3/json")
      .to_return({ status: 200, body: package_json.to_json })
    
    status = @ecosystem.check_status(@package)
    assert_equal status, 'archived'
  end

  test 'check_status returns nil for active status' do
    package_json = JSON.parse(file_fixture('pypi/yiban').read)
    package_json['project-status'] = { 'status' => 'active' }
    
    stub_request(:get, "https://pypi.org/project/urllib3/")
      .to_return({ status: 200, body: '' })
    stub_request(:get, "https://pypi.org/pypi/urllib3/json")
      .to_return({ status: 200, body: package_json.to_json })
    
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status returns removed for 404' do
    stub_request(:get, "https://pypi.org/project/urllib3/")
      .to_return({ status: 404 })

    status = @ecosystem.check_status(@package)
    assert_equal status, 'removed'
  end

  test 'parse_repository_url prefers Repository key over Changelog in project_urls' do
    # This test demonstrates the bug: mkdocstrings has both Changelog and Repository URLs
    # The Changelog URL comes first alphabetically and is incorrectly chosen
    # The correct Repository URL should be https://github.com/mkdocstrings/mkdocstrings
    mkdocstrings_data = JSON.parse(file_fixture('pypi/mkdocstrings.json').read)

    repository_url = @ecosystem.parse_repository_url(mkdocstrings_data)

    # This should be the Repository URL, not the Changelog URL
    assert_equal 'https://github.com/mkdocstrings/mkdocstrings', repository_url
  end

  test 'parse_repository_url falls back to other URLs when Repository key not present' do
    # Test that fallback behavior still works when there's no Repository key
    package_data = {
      "info" => {
        "name" => "test-package",
        "project_urls" => {
          "Homepage" => "https://test-package.github.io",
          "Issues" => "https://github.com/test/test-package/issues",
          "Changelog" => "https://github.com/test/test-package/blob/main/CHANGELOG.md"
        },
        "home_page" => nil
      }
    }

    repository_url = @ecosystem.parse_repository_url(package_data)

    # Should extract the GitHub repo URL from Issues URL
    assert_equal 'https://github.com/test/test-package', repository_url
  end

  test 'parse_repository_url prioritizes Source key over other URLs' do
    # Test that Source key is prioritized
    package_data = {
      "info" => {
        "name" => "test-package",
        "project_urls" => {
          "Documentation" => "https://github.com/other/docs",
          "Source" => "https://github.com/test/test-package",
          "Changelog" => "https://github.com/another/changelog"
        },
        "home_page" => nil
      }
    }

    repository_url = @ecosystem.parse_repository_url(package_data)

    # Should pick the Source URL
    assert_equal 'https://github.com/test/test-package', repository_url
  end

  test 'pypi package_metadata funding_url flask' do
    stub_request(:get, "https://pypi.org/pypi/flask/json")
      .to_return({ status: 200, body: file_fixture('pypi/flask/flask') })
    stub_request(:get, "https://pypistats.org/api/packages/flask/recent")
      .to_return({ status: 200, body: file_fixture('pypi/flask/recent') })
    stub_request(:get, "https://palletsprojects.com/donate")
      .to_return({ status: 200, body: '' })
    package_metadata = @ecosystem.package_metadata('flask')

    assert_equal package_metadata[:name], "flask"
    assert_equal package_metadata[:description], "A simple framework for building complex web applications."
    assert_nil package_metadata[:homepage]
    assert_equal package_metadata[:licenses], ""
    assert_equal package_metadata[:repository_url], "https://github.com/pallets/flask"
    assert_equal package_metadata[:keywords_array], []
    assert_equal package_metadata[:downloads], 157236987
    assert_equal package_metadata[:downloads_period], "last-month"
    assert_equal package_metadata[:metadata], {
      "funding"=> "https://palletsprojects.com/donate",
      "documentation" => "https://flask.palletsprojects.com/",
      "classifiers"=> [
        "Development Status :: 5 - Production/Stable",
        "Environment :: Web Environment",
        "Framework :: Flask",
        "Intended Audience :: Developers",
        "Operating System :: OS Independent",
        "Programming Language :: Python",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Internet :: WWW/HTTP :: WSGI",
        "Topic :: Internet :: WWW/HTTP :: WSGI :: Application",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Typing :: Typed"
      ],
      "normalized_name"=>"flask",
      "project_status"=>nil
    }
  end
end
