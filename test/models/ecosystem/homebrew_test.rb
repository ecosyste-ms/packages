require "test_helper"

class HomebrewTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'Homebrew.org', url: 'https://homebrew.org', ecosystem: 'homebrew')
    @ecosystem = Ecosystem::Homebrew.new(@registry)
    @package = Package.new(ecosystem: 'homebrew', name: 'abook')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://formulae.brew.sh/formula/abook'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://formulae.brew.sh/formula/abook'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
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
    assert_equal install_command, 'brew install abook'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'brew install abook'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, "https://formulae.brew.sh/formula/abook"
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:brew/abook'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:brew/abook@1.26.8'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://formulae.brew.sh/api/formula.json")
      .to_return({ status: 200, body: file_fixture('homebrew/formula.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 6031
    assert_equal all_package_names.last, 'zzz'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/Homebrew/homebrew-core/commits/master.atom")
      .to_return({ status: 200, body: file_fixture('homebrew/master.atom') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 10
    assert_equal recently_updated_package_names.last, 'jql'
  end

  test 'package_metadata' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/abook.json")
      .to_return({ status: 200, body: file_fixture('homebrew/abook.json') })
    package_metadata = @ecosystem.package_metadata('abook')

    assert_equal package_metadata[:name], "abook"
    assert_equal package_metadata[:description], "Address book with mutt support"
    assert_equal package_metadata[:homepage], "https://abook.sourceforge.io/"
    assert_equal package_metadata[:licenses], "GPL-2.0-only and GPL-2.0-or-later and GPL-3.0-or-later and Public Domain and X11"
    assert_equal package_metadata[:repository_url], ""
    assert_nil package_metadata[:keywords_array]
    assert_equal package_metadata[:downloads], 28
    assert_equal package_metadata[:downloads_period], "last-month"
  end

  test 'versions_metadata' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/abook.json")
      .to_return({ status: 200, body: file_fixture('homebrew/abook.json') })
    package_metadata = @ecosystem.package_metadata('abook')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.6.1"}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/abook.json")
      .to_return({ status: 200, body: file_fixture('homebrew/abook.json') })
    package_metadata = @ecosystem.package_metadata('abook')
    dependencies_metadata = @ecosystem.dependencies_metadata('abook', '0.6.1', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"gettext", :requirements=>"*", :kind=>"runtime", :ecosystem=>"homebrew"},
      {:package_name=>"readline", :requirements=>"*", :kind=>"runtime", :ecosystem=>"homebrew"}
    ]
  end
end
