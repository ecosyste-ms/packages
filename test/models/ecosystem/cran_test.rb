require "test_helper"

class CranTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'cran.r-project.org', url: 'https://cran.r-project.org', ecosystem: 'cran')
    @ecosystem = Ecosystem::Cran.new(@registry.url)
    @package = Package.new(ecosystem: @registry.ecosystem, name: 'pack')
    @version = @package.versions.build(number: '0.1-1')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'https://cran.r-project.org/package=pack'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'https://cran.r-project.org/package=pack'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package.name, @version.number)
    assert_equal download_url, 'https://cran.r-project.org/src/contrib/pack_0.1-1.tar.gz'
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package.name)
    assert_equal documentation_url, "http://cran.r-project.org/web/packages/pack/pack.pdf"
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
    assert_equal documentation_url, "http://cran.r-project.org/web/packages/pack/pack.pdf"
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_nil install_command
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_nil install_command
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "http://cran.r-project.org/web/packages/pack/index.html"
  end

  test 'all_package_names' do
    stub_request(:get, "https://cran.r-project.org/web/packages/available_packages_by_date.html")
      .to_return({ status: 200, body: file_fixture('cran/available_packages_by_date.html') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 19022
    assert_equal all_package_names.last, 'pack'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://cran.r-project.org/web/packages/available_packages_by_date.html")
      .to_return({ status: 200, body: file_fixture('cran/available_packages_by_date.html') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 100
    assert_equal recently_updated_package_names.last, 'beyondWhittle'
  end

  test 'package_metadata' do
    stub_request(:get, "https://cran.r-project.org/web/packages/pack/index.html")
      .to_return({ status: 200, body: file_fixture('cran/index.html') })
    package_metadata = @ecosystem.package_metadata('pack')
    
    assert_equal package_metadata[:name], "pack"
    assert_equal package_metadata[:description], "Convert values to/from raw vectors"
    assert_nil package_metadata[:homepage]
    assert_equal package_metadata[:licenses], "GPL-3"
    assert_equal package_metadata[:repository_url], ""
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://cran.r-project.org/web/packages/pack/index.html")
      .to_return({ status: 200, body: file_fixture('cran/index.html') })
    stub_request(:get, "https://cran.r-project.org/src/contrib/Archive/pack/")
    .to_return({ status: 200, body: file_fixture('cran/archives.html') })
      
    package_metadata = @ecosystem.package_metadata('pack')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [
      {:number=>"0.1-1", :published_at=>"2008-09-08"},
      {:number=>"0.1", :published_at=>"2008-08-17 10:31"}
    ]
  end

  test 'dependencies_metadata' do
    stub_request(:head, "https://cran.rstudio.com/src/contrib/AssetAllocation_0.1.0.tar.gz")
      .to_return({ status: 200 })
    stub_request(:get, "https://cran.rstudio.com/src/contrib/AssetAllocation_0.1.0.tar.gz")
      .to_return({ status: 200, body: file_fixture('cran/AssetAllocation_0.1.0.tar.gz') })
    dependencies_metadata = @ecosystem.dependencies_metadata('AssetAllocation', '0.1.0', nil)

    assert_equal dependencies_metadata, [
      {:package_name=>"R", :requirements=>">= 2.10", :kind=>"depends", :ecosystem=>"cran"},
      {:package_name=>"PerformanceAnalytics", :requirements=>"*", :kind=>"imports", :ecosystem=>"cran"},
      {:package_name=>"quantmod", :requirements=>"*", :kind=>"imports", :ecosystem=>"cran"},
      {:package_name=>"xts", :requirements=>"*", :kind=>"imports", :ecosystem=>"cran"},
      {:package_name=>"zoo", :requirements=>"*", :kind=>"imports", :ecosystem=>"cran"},
      {:package_name=>"knitr", :requirements=>"*", :kind=>"suggests", :ecosystem=>"cran"},
      {:package_name=>"rmarkdown", :requirements=>"*", :kind=>"suggests", :ecosystem=>"cran"},
      {:package_name=>"testthat", :requirements=>">= 3.0.0", :kind=>"suggests", :ecosystem=>"cran"}
    ]
  end

  test 'dependencies_metadata for older versions' do
    stub_request(:head, "https://cran.rstudio.com/src/contrib/ggroups_2.1.0.tar.gz").to_return({ status: 404 })
    stub_request(:get, "https://cran.rstudio.com/src/contrib/Archive/ggroups/ggroups_2.1.0.tar.gz")
      .to_return({ status: 200, body: file_fixture('cran/ggroups_2.1.0.tar.gz') })

    dependencies_metadata = @ecosystem.dependencies_metadata('ggroups', '2.1.0', nil)

    assert_equal dependencies_metadata, [
      {:package_name=>"doParallel", :requirements=>">= 1.0.14", :kind=>"suggests", :ecosystem=>"cran"},
      {:package_name=>"foreach", :requirements=>">= 1.4.4", :kind=>"suggests", :ecosystem=>"cran"}
    ]
  end
end
