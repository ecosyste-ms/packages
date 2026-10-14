require "test_helper"

class HomebrewTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Homebrew.org', url: 'https://homebrew.org', ecosystem: 'homebrew')
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

  test 'check_status reuses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/abook.json")
      .to_return({ status: 200, body: file_fixture('homebrew/abook.json') })

    # Fetch metadata first to populate the cache
    @ecosystem.package_metadata('abook')

    # check_status should reuse cached data
    status = @ecosystem.check_status(@package)
    assert_nil status

    # The formula JSON should only have been fetched once (for the initial fetch)
    assert_requested(:get, "https://formulae.brew.sh/api/formula/abook.json", times: 1)
    # The formula page should NOT have been hit
    assert_not_requested(:head, "https://formulae.brew.sh/formula/abook")
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

  test 'repository_url prefers git head url over marketing homepage' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/githead.json")
      .to_return({ status: 200, body: file_fixture('homebrew/githead.json') })
    package_metadata = @ecosystem.package_metadata('githead')

    assert_equal "https://githead.example.com", package_metadata[:homepage]
    assert_equal "https://github.com/foo/githead", package_metadata[:repository_url]
  end

  test 'repository_url uses stable source archive url when no git head' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/archivetool.json")
      .to_return({ status: 200, body: file_fixture('homebrew/archivetool.json') })
    package_metadata = @ecosystem.package_metadata('archivetool')

    assert_equal "https://github.com/bar/archivetool", package_metadata[:repository_url]
  end

  test 'repository_url preserves explicit git sources on unrecognized hosts' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/aom.json")
      .to_return({ status: 200, body: file_fixture('homebrew/aom.json') })
    package_metadata = @ecosystem.package_metadata('aom')

    assert_equal "https://aomedia.googlesource.com/aom", package_metadata[:repository_url]
  end

  test 'repository_url preserves an explicit stable git source without a head' do
    formula = JSON.parse(file_fixture('homebrew/aom.json').read)
    formula['urls'].delete('head')
    stub_request(:get, "https://formulae.brew.sh/api/formula/aom.json")
      .to_return({ status: 200, body: formula.to_json })

    assert_equal "https://aomedia.googlesource.com/aom", @ecosystem.package_metadata('aom')[:repository_url]
  end

  test 'repository_url prefers an explicit git source over a recognized homepage' do
    formula = JSON.parse(file_fixture('homebrew/aom.json').read)
    formula['homepage'] = 'https://github.com/Homebrew/homebrew-core'
    stub_request(:get, "https://formulae.brew.sh/api/formula/aom.json")
      .to_return({ status: 200, body: formula.to_json })

    assert_equal "https://aomedia.googlesource.com/aom", @ecosystem.package_metadata('aom')[:repository_url]
  end

  test 'repository_url preserves a git protocol source without a git extension' do
    formula = JSON.parse(file_fixture('homebrew/aom.json').read)
    formula['urls']['head']['url'] = 'git://example.com/aom'
    stub_request(:get, "https://formulae.brew.sh/api/formula/aom.json")
      .to_return({ status: 200, body: formula.to_json })

    assert_equal "https://example.com/aom", @ecosystem.package_metadata('aom')[:repository_url]
  end

  test 'repository_url falls back to homepage when sources are not forge repos' do
    stub_request(:get, "https://formulae.brew.sh/api/formula/abook.json")
      .to_return({ status: 200, body: file_fixture('homebrew/abook.json') })
    package_metadata = @ecosystem.package_metadata('abook')

    assert_equal "", package_metadata[:repository_url]
  end

  test 'repository_url normalizes explicit git schemes and extensions' do
    ['git://example.com/aom.git', 'git+https://example.com/aom.git', 'https://example.com/aom.git'].each do |url|
      formula = { 'urls' => { 'head' => { 'url' => url } } }

      assert_equal 'https://example.com/aom', @ecosystem.repository_url(formula)
    end
  end

  test 'repository_url accepts git metadata without a git extension' do
    ['head', 'stable'].each do |kind|
      formula = { 'urls' => { kind => { 'url' => 'https://git.notmuchmail.org/git/notmuch', 'using' => 'git' } } }

      assert_equal 'https://git.notmuchmail.org/git/notmuch', @ecosystem.repository_url(formula)
    end
  end

  test 'repository_url does not treat null using svn sources as git' do
    [nil, 'svn'].each do |using|
      formula = {
        'homepage' => 'https://astyle.sourceforge.net/',
        'urls' => { 'head' => { 'url' => 'https://svn.code.sf.net/p/astyle/code/trunk', 'using' => using } }
      }

      assert_equal '', @ecosystem.repository_url(formula)
      formula['homepage'] = 'https://github.com/foo/astyle'
      assert_equal 'https://github.com/foo/astyle', @ecosystem.repository_url(formula)
    end
  end

  test 'repository_url skips missing source urls and keeps stable fallback' do
    formula = {
      'urls' => {
        'head' => { 'url' => nil, 'using' => 'git' },
        'stable' => { 'url' => 'https://github.com/bar/archivetool/archive/v1.0.tar.gz' }
      }
    }

    assert_equal 'https://github.com/bar/archivetool', @ecosystem.repository_url(formula)
  end

  test 'repository_url normalizes git schemes on recognized hosts' do
    ['git://github.com/foo/aom.git', 'git+https://github.com/foo/aom.git'].each do |url|
      formula = { 'urls' => { 'head' => { 'url' => url } } }

      assert_equal 'https://github.com/foo/aom', @ecosystem.repository_url(formula)
    end
  end
end
