require "test_helper"

class JuliaTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'pkg.julialang.org', url: 'http://pkg.julialang.org/', ecosystem: 'julia')
    @ecosystem = Ecosystem::Julia.new(@registry.url)
    @package = Package.new(ecosystem: 'julia', name: 'Inequality')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'package_url' do
    package_url = @ecosystem.package_url(@package)
    assert_equal package_url, 'http://formulae.brew.sh/formula/Inequality'
  end

  test 'package_url with version' do
    package_url = @ecosystem.package_url(@package, @version.number)
    assert_equal package_url, 'http://formulae.brew.sh/formula/Inequality'
  end

  # test 'download_url' do
  #   download_url = @ecosystem.download_url(@package.name, @version.number)
  #   assert_nil download_url
  # end

  # test 'documentation_url' do
  #   documentation_url = @ecosystem.documentation_url(@package.name)
  #   assert_nil documentation_url
  # end

  # test 'documentation_url with version' do
  #   documentation_url = @ecosystem.documentation_url(@package.name, @version.number)
  #   assert_nil documentation_url
  # end

  # test 'install_command' do
  #   install_command = @ecosystem.install_command(@package)
  #   assert_equal install_command, 'brew install Inequality'
  # end

  # test 'install_command with version' do
  #   install_command = @ecosystem.install_command(@package, @version.number)
  #   assert_equal install_command, 'brew install Inequality'
  # end

  # test 'check_status_url' do
  #   check_status_url = @ecosystem.check_status_url(@package)
  #   assert_equal check_status_url, "http://formulae.brew.sh/formula/Inequality"
  # end

  test 'all_package_names' do
    stub_request(:get, "https://juliahub.com/app/packages/info")
      .to_return({ status: 200, body: file_fixture('julia/info') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 7442
    assert_equal all_package_names.last, 'ZygoteStructArrays'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/JuliaRegistries/General/commits/master/Registry.toml.atom")
      .to_return({ status: 200, body: file_fixture('julia/Registry.toml.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 20
    assert_equal recently_updated_package_names.last, 'Inequality'
  end

  # test 'package_metadata' do
  #   stub_request(:get, "https://formulae.brew.sh/api/formula/Inequality.json")
  #     .to_return({ status: 200, body: file_fixture('julia/Inequality.json') })
  #   package_metadata = @ecosystem.package_metadata('Inequality')
    
  #   assert_equal package_metadata[:name], "Inequality"
  #   assert_equal package_metadata[:description], "Address book with mutt support"
  #   assert_equal package_metadata[:homepage], "https://Inequality.sourceforge.io/"
  #   assert_equal package_metadata[:licenses], "GPL-2.0-only and GPL-2.0-or-later and GPL-3.0-or-later and Public Domain and X11"
  #   assert_equal package_metadata[:repository_url], ""
  #   assert_nil package_metadata[:keywords_array]
  # end

  # test 'versions_metadata' do
  #   stub_request(:get, "https://formulae.brew.sh/api/formula/Inequality.json")
  #     .to_return({ status: 200, body: file_fixture('julia/Inequality.json') })
  #   package_metadata = @ecosystem.package_metadata('Inequality')
  #   versions_metadata = @ecosystem.versions_metadata(package_metadata)

  #   assert_equal versions_metadata, [{:number=>"0.6.1"}]
  # end

  # test 'dependencies_metadata' do
  #   stub_request(:get, "https://formulae.brew.sh/api/formula/Inequality.json")
  #     .to_return({ status: 200, body: file_fixture('julia/Inequality.json') })
  #   package_metadata = @ecosystem.package_metadata('Inequality')
  #   dependencies_metadata = @ecosystem.dependencies_metadata('Inequality', '0.6.1', package_metadata)

  #   assert_equal dependencies_metadata, [
  #     {:package_name=>"gettext", :requirements=>"*", :kind=>"runtime", :ecosystem=>"homebrew"},
  #     {:package_name=>"readline", :requirements=>"*", :kind=>"runtime", :ecosystem=>"homebrew"}
  #   ]
  # end
end
