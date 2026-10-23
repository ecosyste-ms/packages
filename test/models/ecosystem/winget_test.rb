# frozen_string_literal: true

require 'test_helper'

class WingetTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'winstall.app', url: 'https://winstall.app', ecosystem: 'winget')
    @ecosystem = Ecosystem::Winget.new(@registry)
    @package = Package.new(ecosystem: 'winget', name: '7zip.7zip')
    @version = @package.versions.build(number: '26.05')
  end

  test 'registry_url' do
    assert_equal 'https://winstall.app/apps/7zip.7zip', @ecosystem.registry_url(@package)
  end

  test 'install_command' do
    assert_equal 'winget install --id 7zip.7zip', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'winget install --id 7zip.7zip --version 26.05', @ecosystem.install_command(@package, @version)
  end

  test 'check_status_url' do
    assert_equal 'https://api.winstall.app/apps/7zip.7zip', @ecosystem.check_status_url(@package)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:winget/7zip.7zip', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:winget/7zip.7zip@26.05', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    response_body = {
      'total' => 2,
      'offset' => 0,
      'limit' => 1000,
      'data' => [
        { '_id' => '7zip.7zip' },
        { '_id' => 'Google.Chrome' }
      ]
    }.to_json

    stub_request(:get, 'https://api.winstall.app/apps?limit=1000&offset=0')
      .to_return(status: 200, body: response_body, headers: { 'Content-Type' => 'application/json' })

    names = @ecosystem.all_package_names
    assert_equal ['7zip.7zip', 'Google.Chrome'], names
  end

  test 'recently_updated_package_names' do
    atom_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <title>New version: Vita3K.Vita3K version 0.2.1.4219 (#460280)</title>
        </entry>
        <entry>
          <title>New package: hatayama.uloop version 3.11.0 (#460285)</title>
        </entry>
      </feed>
    XML

    stub_request(:get, 'https://github.com/microsoft/winget-pkgs/commits/master.atom')
      .to_return(status: 200, body: atom_xml, headers: { 'Content-Type' => 'application/atom+xml' })

    names = @ecosystem.recently_updated_package_names
    assert_includes names, 'Vita3K.Vita3K'
    assert_includes names, 'hatayama.uloop'
  end

  test 'package_metadata' do
    app_data = {
      '_id' => '7zip.7zip',
      'name' => '7-Zip',
      'desc' => 'A file archiver with a high compression ratio.',
      'homepage' => 'https://7-zip.org/download.html',
      'license' => 'LGPL-2.1',
      'latestVersion' => '26.05',
      'updatedAt' => '2026-10-21T15:30:04.479Z',
      'publisher' => 'Igor Pavlov',
      'tags' => ['archive', 'zip'],
      'versions' => [
        {
          'version' => '26.05',
          'installers' => ['https://github.com/ip7z/7zip/releases/download/26.05/7z2605-x64.exe']
        }
      ]
    }.to_json

    stub_request(:get, 'https://api.winstall.app/apps/7zip.7zip')
      .to_return(status: 200, body: app_data, headers: { 'Content-Type' => 'application/json' })

    metadata = @ecosystem.package_metadata('7zip.7zip')
    assert_equal '7zip.7zip', metadata[:name]
    assert_equal 'A file archiver with a high compression ratio.', metadata[:description]
    assert_equal 'https://7-zip.org/download.html', metadata[:homepage]
    assert_equal 'LGPL-2.1', metadata[:licenses]
    assert_equal '26.05', metadata[:version]
    assert_includes metadata[:keywords_array], 'archive'
  end

  test 'versions_metadata' do
    pkg_metadata = {
      name: '7zip.7zip',
      updated_at: '2026-10-21T15:30:04.479Z',
      versions: [
        {
          'version' => '26.05',
          'installers' => ['https://github.com/ip7z/7zip/releases/download/26.05/7z2605-x64.exe']
        },
        {
          'version' => '26.04',
          'installers' => ['https://7-zip.org/a/7z2604-x64.exe']
        }
      ]
    }

    versions = @ecosystem.versions_metadata(pkg_metadata)
    assert_equal 2, versions.length
    assert_equal '26.05', versions[0][:number]
    assert_equal 'https://github.com/ip7z/7zip/releases/download/26.05/7z2605-x64.exe', versions[0][:download_url]
    assert_equal '26.04', versions[1][:number]
  end

  test 'check_status returns nil when app exists' do
    app_data = { '_id' => '7zip.7zip', 'name' => '7-Zip' }.to_json
    stub_request(:get, 'https://api.winstall.app/apps/7zip.7zip')
      .to_return(status: 200, body: app_data, headers: { 'Content-Type' => 'application/json' })

    assert_nil @ecosystem.check_status(@package)
  end

  test 'check_status returns removed when 404' do
    stub_request(:get, 'https://api.winstall.app/apps/7zip.7zip')
      .to_return(status: 404, body: '')
    stub_request(:head, 'https://api.winstall.app/apps/7zip.7zip')
      .to_return(status: 404, body: '')

    assert_equal 'removed', @ecosystem.check_status(@package)
  end
end
