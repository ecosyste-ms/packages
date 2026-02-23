require "test_helper"

class CtanTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'CTAN', url: 'https://ctan.org', ecosystem: 'ctan')
    @ecosystem = Ecosystem::Ctan.new(@registry)
    @package = Package.new(ecosystem: 'ctan', name: 'jigsaw', metadata: { 'ctan_path' => '/graphics/pgf/contrib/jigsaw' })
    @version = @package.versions.build(number: '0.5')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://ctan.org/pkg/jigsaw'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://ctan.org/pkg/jigsaw'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_equal download_url, 'https://mirrors.ctan.org/graphics/pgf/contrib/jigsaw.zip'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'tlmgr install jigsaw'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'tlmgr install jigsaw'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://ctan.org/pkg/jigsaw'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:ctan/jigsaw'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:ctan/jigsaw@0.5'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, "https://ctan.org/json/2.0/packages")
      .to_return({ status: 200, body: file_fixture('ctan/packages.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal all_package_names.length, 3
    assert_equal all_package_names.last, 'a2ping'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://ctan.org/ctan-ann/rss")
      .to_return({ status: 200, body: file_fixture('ctan/rss.xml') })
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal recently_updated_package_names.length, 4
    assert_equal recently_updated_package_names.first, 'fariscovernew'
  end

  test 'package_metadata' do
    stub_request(:get, "https://ctan.org/json/2.0/pkg/jigsaw")
      .to_return({ status: 200, body: file_fixture('ctan/jigsaw.json') })
    package_metadata = @ecosystem.package_metadata('jigsaw')

    assert_equal package_metadata[:name], "jigsaw"
    assert_equal package_metadata[:description], "This is a small LaTeX package to draw jigsaw pieces with TikZ. It is possible to draw individual pieces and adjust their shape, create tile patterns or automatically generate complete jigsaws."
    assert_equal package_metadata[:licenses], "LPPL-1.3c"
    assert_equal package_metadata[:repository_url], "https://github.com/samcarter/jigsaw"
    assert_equal package_metadata[:keywords_array], ["pgf-tikz"]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://ctan.org/json/2.0/pkg/jigsaw")
      .to_return({ status: 200, body: file_fixture('ctan/jigsaw.json') })
    package_metadata = @ecosystem.package_metadata('jigsaw')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{ number: "0.5", published_at: "2024-04-25" }]
  end

  test 'maintainers_metadata' do
    stub_request(:get, "https://ctan.org/json/2.0/pkg/jigsaw")
      .to_return({ status: 200, body: file_fixture('ctan/jigsaw.json') })
    stub_request(:get, "https://ctan.org/json/2.0/author/samcarter")
      .to_return({ status: 200, body: file_fixture('ctan/author-samcarter.json') })

    maintainers = @ecosystem.maintainers_metadata('jigsaw')

    assert_equal maintainers.length, 1
    assert_equal maintainers.first[:uuid], "samcarter"
    assert_equal maintainers.first[:name], "Sam Carter"
  end

  test 'check_status reuses memoized metadata without extra HTTP request' do
    stub_request(:get, "https://ctan.org/json/2.0/pkg/jigsaw")
      .to_return({ status: 200, body: file_fixture('ctan/jigsaw.json') })

    @ecosystem.package_metadata('jigsaw')

    status = @ecosystem.check_status(@package)
    assert_nil status

    assert_requested(:get, "https://ctan.org/json/2.0/pkg/jigsaw", times: 1)
    assert_not_requested(:head, "https://ctan.org/pkg/jigsaw")
  end

  test 'license mapping' do
    assert_equal Ecosystem::Ctan::SPDX_MAP['lppl1.3c'], 'LPPL-1.3c'
    assert_equal Ecosystem::Ctan::SPDX_MAP['gpl3'], 'GPL-3.0-only'
    assert_equal Ecosystem::Ctan::SPDX_MAP['mit'], 'MIT'
    assert_equal Ecosystem::Ctan::SPDX_MAP['apache2'], 'Apache-2.0'
    assert_equal Ecosystem::Ctan::SPDX_MAP['cc0'], 'CC0-1.0'
    assert_equal Ecosystem::Ctan::SPDX_MAP['ofl'], 'OFL-1.1'
    assert_equal Ecosystem::Ctan::SPDX_MAP['pd'], 'Public Domain'
    assert_nil Ecosystem::Ctan::SPDX_MAP['unknown-license']
  end
end
