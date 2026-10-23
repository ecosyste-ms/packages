# frozen_string_literal: true

require "test_helper"

class PeclTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'pecl.php.net', url: 'https://pecl.php.net', ecosystem: 'pecl')
    @ecosystem = Ecosystem::Pecl.new(@registry)
    @package = Package.new(ecosystem: 'pecl', name: 'apcu')
    @version = @package.versions.build(number: '5.1.28')
    @maintainer = @registry.maintainers.build(login: 'nikic')
  end

  test 'registry_url' do
    assert_equal 'https://pecl.php.net/package/apcu', @ecosystem.registry_url(@package)
  end

  test 'registry_url with version' do
    assert_equal 'https://pecl.php.net/package/apcu/5.1.28', @ecosystem.registry_url(@package, @version)
  end

  test 'download_url' do
    assert_equal 'https://pecl.php.net/get/apcu-5.1.28.tgz', @ecosystem.download_url(@package, @version)
  end

  test 'install_command' do
    assert_equal 'pecl install apcu', @ecosystem.install_command(@package)
  end

  test 'install_command with version' do
    assert_equal 'pecl install apcu-5.1.28', @ecosystem.install_command(@package, @version.number)
  end

  test 'purl' do
    assert_equal 'pkg:pecl/apcu', @ecosystem.purl(@package)
  end

  test 'purl with version' do
    assert_equal 'pkg:pecl/apcu@5.1.28', @ecosystem.purl(@package, @version)
  end

  test 'all_package_names' do
    xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <a xmlns="http://pear.php.net/dtd/rest.allpackages">
        <c>pecl.php.net</c>
        <p>apcu</p>
        <p>redis</p>
      </a>
    XML
    stub_request(:get, "https://pecl.php.net/rest/p/packages.xml")
      .to_return(status: 200, body: xml)

    names = @ecosystem.all_package_names
    assert_equal ['apcu', 'redis'], names
  end

  test 'recently_updated_package_names' do
    rss = <<-XML
      <?xml version="1.0" encoding="utf-8"?>
      <rdf:RDF xmlns="http://purl.org/rss/1.0/">
        <channel>
          <title>PECL</title>
        </channel>
        <item>
          <title>apcu 5.1.28</title>
        </item>
        <item>
          <title>redis 6.0.2</title>
        </item>
      </rdf:RDF>
    XML
    stub_request(:get, "https://pecl.php.net/feeds/latest.rss")
      .to_return(status: 200, body: rss)

    names = @ecosystem.recently_updated_package_names
    assert_equal ['apcu', 'redis'], names
  end

  test 'package_metadata' do
    info_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <p xmlns="http://pear.php.net/dtd/rest.package">
        <n>APCu</n>
        <c>pecl.php.net</c>
        <ca>Caching</ca>
        <l>PHP License</l>
        <s>APCu - APC User Cache</s>
        <d>APC User Caching</d>
      </p>
    XML
    releases_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <a xmlns="http://pear.php.net/dtd/rest.allreleases">
        <r><v>5.1.28</v></r>
        <r><v>5.1.27</v></r>
      </a>
    XML
    stub_request(:get, "https://pecl.php.net/rest/p/apcu/info.xml")
      .to_return(status: 200, body: info_xml)
    stub_request(:get, "https://pecl.php.net/rest/r/apcu/allreleases.xml")
      .to_return(status: 200, body: releases_xml)

    data = @ecosystem.fetch_package_metadata_uncached('apcu')
    assert_equal 'APCu', data[:name]
    assert_equal 'PHP License', data[:licenses]
    assert_equal ['5.1.28', '5.1.27'], data[:versions]
    assert_equal ['Caching'], data[:keywords_array]
  end

  test 'versions_metadata' do
    version_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <r xmlns="http://pear.php.net/dtd/rest.release">
        <v>5.1.28</v>
        <da>2025-12-07 08:01:05</da>
        <l>PHP License</l>
        <g>https://pecl.php.net/get/apcu-5.1.28</g>
        <s>APCu - APC User Cache</s>
        <d>APC User Caching</d>
        <st>stable</st>
      </r>
    XML
    stub_request(:get, "https://pecl.php.net/rest/r/apcu/5.1.28.xml")
      .to_return(status: 200, body: version_xml)

    pkg_meta = { name: 'apcu', versions: ['5.1.28'], licenses: 'PHP License' }
    versions = @ecosystem.versions_metadata(pkg_meta)
    assert_equal 1, versions.length
    assert_equal '5.1.28', versions.first[:number]
    assert_equal 'PHP License', versions.first[:licenses]
    assert_equal Time.parse('2025-12-07 08:01:05'), versions.first[:published_at]
  end

  test 'maintainers_metadata' do
    info_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <p xmlns="http://pear.php.net/dtd/rest.package">
        <n>APCu</n>
      </p>
    XML
    releases_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <a xmlns="http://pear.php.net/dtd/rest.allreleases">
        <r><v>5.1.28</v></r>
      </a>
    XML
    version_xml = <<-XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <r xmlns="http://pear.php.net/dtd/rest.release">
        <v>5.1.28</v>
        <m>nikic</m>
      </r>
    XML
    stub_request(:get, "https://pecl.php.net/rest/p/apcu/info.xml")
      .to_return(status: 200, body: info_xml)
    stub_request(:get, "https://pecl.php.net/rest/r/apcu/allreleases.xml")
      .to_return(status: 200, body: releases_xml)
    stub_request(:get, "https://pecl.php.net/rest/r/apcu/5.1.28.xml")
      .to_return(status: 200, body: version_xml)

    maintainers = @ecosystem.maintainers_metadata('apcu')
    assert_equal 1, maintainers.length
    assert_equal 'nikic', maintainers.first[:login]
  end

  test 'maintainer_url' do
    assert_equal 'https://pecl.php.net/user/nikic', @ecosystem.maintainer_url(@maintainer)
  end
end
