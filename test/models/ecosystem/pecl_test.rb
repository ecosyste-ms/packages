require "test_helper"

class PeclTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: "pecl.php.net", url: "https://pecl.php.net", ecosystem: "pecl", default: true)
    @ecosystem = Ecosystem::Pecl.new(@registry)
    @package = Package.new(ecosystem: "pecl", name: "redis")
    @version = @package.versions.build(number: "6.2.0")
  end

  test "registry_url" do
    assert_equal "https://pecl.php.net/package/redis", @ecosystem.registry_url(@package)
  end

  test "registry_url with version" do
    assert_equal "https://pecl.php.net/package/redis/6.2.0", @ecosystem.registry_url(@package, @version)
  end

  test "install_command" do
    assert_equal "pecl install redis", @ecosystem.install_command(@package)
    assert_equal "pecl install redis-6.2.0", @ecosystem.install_command(@package, "6.2.0")
  end

  test "check_status_url" do
    assert_equal "https://pecl.php.net/rest/p/redis/info.xml", @ecosystem.check_status_url(@package)
  end

  test "all_package_names" do
    stub_request(:get, "https://pecl.php.net/rest/p/packages.xml")
      .to_return(
        status: 200,
        body: <<~XML,
          <?xml version="1.0" encoding="UTF-8" ?>
          <a xmlns="http://pear.php.net/dtd/rest.allpackages">
            <c>pecl.php.net</c>
            <p>redis</p>
            <p>amqp</p>
          </a>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    assert_equal ["redis", "amqp"], @ecosystem.all_package_names
  end

  test "package_metadata" do
    stub_request(:get, "https://pecl.php.net/rest/p/redis/info.xml")
      .to_return(
        status: 200,
        body: <<~XML,
          <?xml version="1.0" encoding="UTF-8" ?>
          <p xmlns="http://pear.php.net/dtd/rest.package">
            <n>redis</n>
            <c>pecl.php.net</c>
            <ca>Database</ca>
            <l>PHP</l>
            <s>PHP extension for Redis</s>
            <d>Communicates with RESP-based key-value stores.</d>
          </p>
        XML
        headers: { "Content-Type" => "application/xml" }
      )
    stub_request(:get, "https://pecl.php.net/rest/r/redis/allreleases.xml")
      .to_return(
        status: 200,
        body: <<~XML,
          <?xml version="1.0" encoding="UTF-8" ?>
          <a xmlns="http://pear.php.net/dtd/rest.allreleases">
            <p>redis</p>
            <c>pecl.php.net</c>
            <r><v>6.2.0</v><s>stable</s></r>
          </a>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    metadata = @ecosystem.package_metadata("redis")

    assert_equal "redis", metadata[:name]
    assert_equal "PHP extension for Redis", metadata[:description]
    assert_equal "https://pecl.php.net/package/redis", metadata[:homepage]
    assert_equal "Database", metadata[:metadata][:category]
  end

  test "versions_metadata" do
    stub_request(:get, "https://pecl.php.net/rest/r/redis/6.2.0.xml")
      .to_return(
        status: 200,
        body: <<~XML,
          <?xml version="1.0" encoding="UTF-8" ?>
          <r xmlns="http://pear.php.net/dtd/rest.release">
            <p>redis</p>
            <v>6.2.0</v>
            <st>stable</st>
            <l>PHP</l>
            <s>PHP extension for Redis</s>
            <d>Communicates with RESP-based key-value stores.</d>
            <da>2025-03-24 19:05:36</da>
            <n>Release notes</n>
          </r>
        XML
        headers: { "Content-Type" => "application/xml" }
      )

    releases = Nokogiri::XML(<<~XML)
      <?xml version="1.0" encoding="UTF-8" ?>
      <a xmlns="http://pear.php.net/dtd/rest.allreleases">
        <r><v>6.2.0</v><s>stable</s></r>
      </a>
    XML

    versions = @ecosystem.versions_metadata({ name: "redis", releases: releases })

    assert_equal 1, versions.length
    assert_equal "6.2.0", versions.first[:number]
    assert_equal "2025-03-24 19:05:36", versions.first[:published_at]
    assert_equal "stable", versions.first[:metadata][:status]
    assert_equal "Release notes", versions.first[:metadata][:notes]
  end

  test "purl uses pear type" do
    assert_equal "pear", @ecosystem.purl_type
  end
end
