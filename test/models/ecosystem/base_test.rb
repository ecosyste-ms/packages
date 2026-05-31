require "test_helper"

class BaseTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create(name: 'Test Registry', url: 'https://test.example.com', ecosystem: 'test')
    @ecosystem = Ecosystem::Base.new(@registry)
    @package = @registry.packages.create(ecosystem: 'test', name: 'test-package')
  end

  test 'check_status returns nil when URL is blank' do
    @package.update(repository_url: nil, homepage: nil)
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status returns nil when URL is invalid' do
    # Create a package with an invalid URI in repository_url
    invalid_package = @registry.packages.create(
      ecosystem: 'test',
      name: 'invalid-uri-package',
      repository_url: 'https://MTAnalytics (#11070)'
    )

    # Mock check_status_url to return the invalid URL
    @ecosystem.stubs(:check_status_url).returns('https://MTAnalytics (#11070)')
    status = @ecosystem.check_status(invalid_package)
    assert_nil status
  end

  test 'check_status returns removed for 404 status' do
    stub_request(:head, "https://example.com/package")
      .to_return(status: 404)

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_equal 'removed', status
  end

  test 'check_status returns removed for 410 status' do
    stub_request(:head, "https://example.com/package")
      .to_return(status: 410)

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_equal 'removed', status
  end

  test 'check_status returns nil for 200 status' do
    stub_request(:head, "https://example.com/package")
      .to_return(status: 200)

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'check_status handles Faraday errors gracefully' do
    stub_request(:head, "https://example.com/package")
      .to_raise(Faraday::ConnectionFailed.new('Connection failed'))

    @ecosystem.stubs(:check_status_url).returns('https://example.com/package')
    status = @ecosystem.check_status(@package)
    assert_nil status
  end

  test 'download_and_cache returns nil when wget fails to download' do
    cache_dir = Rails.root.join('tmp', 'cache', 'ecosystems')
    FileUtils.mkdir_p(cache_dir)
    cached_file = cache_dir.join('test-wget-fail')
    FileUtils.rm_f(cached_file)

    result = @ecosystem.download_and_cache('https://nonexistent.example.com/file.tar.gz', 'test-wget-fail', ttl: 0.seconds)

    assert_nil result
    FileUtils.rm_f(cached_file)
  end

  test 'download_and_cache returns nil when tar extraction produces no files' do
    cache_dir = Rails.root.join('tmp', 'cache', 'ecosystems')
    FileUtils.mkdir_p(cache_dir)
    cached_file = cache_dir.join('test-tar-fail')
    FileUtils.rm_f(cached_file)

    Dir.mktmpdir do |test_dir|
      empty_tar = File.join(test_dir, 'empty.tar.gz')
      `tar -czf #{empty_tar} -T /dev/null`

      test_url = "file://#{empty_tar}"

      result = @ecosystem.download_and_cache(test_url, 'test-tar-fail', ttl: 0.seconds)

      assert_nil result
    end

    FileUtils.rm_f(cached_file)
  end

  test 'download_and_cache deletes stale cache when download fails' do
    cache_dir = Rails.root.join('tmp', 'cache', 'ecosystems')
    FileUtils.mkdir_p(cache_dir)
    cached_file = cache_dir.join('test-stale-cache')
    File.write(cached_file, 'old stale content')
    old_time = 2.hours.ago.to_time
    File.utime(old_time, old_time, cached_file)

    result = @ecosystem.download_and_cache('https://nonexistent.example.com/file.tar.gz', 'test-stale-cache', ttl: 0.seconds)

    assert_nil result
    assert_not cached_file.exist?, 'Stale cache should be deleted after failed download'
  end

  test 'parse_apkindex returns empty array when file is nil' do
    result = @ecosystem.parse_apkindex(nil)
    assert_equal [], result
  end

  test 'parse_apkindex returns empty array when file does not exist' do
    result = @ecosystem.parse_apkindex('/nonexistent/file/path')
    assert_equal [], result
  end

  test 'name_from_purl joins namespace by default' do
    purl = Purl.parse('pkg:npm/@babel/core@7.0.0')
    assert_equal '@babel/core', Ecosystem::Base.name_from_purl(purl)
  end

  test 'name_from_purl defaults docker namespace to library' do
    purl = Purl.parse('pkg:docker/redis@7')
    assert_equal 'library/redis', Ecosystem::Base.name_from_purl(purl)
  end

  test 'name_from_purl drops distro namespace for apk' do
    purl = Purl.parse('pkg:apk/alpine/jq@1.7.1-r0')
    assert_equal 'jq', Ecosystem::Base.name_from_purl(purl)
  end

  test 'name_from_purl drops distro namespace for deb' do
    purl = Purl.parse('pkg:deb/debian/curl@8.5.0-2')
    assert_equal 'curl', Ecosystem::Base.name_from_purl(purl)
  end

  test 'name_from_purl drops distro namespace for alpm' do
    purl = Purl.parse('pkg:alpm/arch/jq@1.8.1-3?arch=x86_64')
    assert_equal 'jq', Ecosystem::Base.name_from_purl(purl)
  end

  test 'purl_type_to_ecosystems returns all matching ecosystems for apk' do
    ecosystems = Ecosystem::Base.purl_type_to_ecosystems('apk')
    assert_includes ecosystems, 'alpine'
    assert_includes ecosystems, 'adelie'
    assert_includes ecosystems, 'postmarketos'
  end

  test 'purl_type_to_ecosystems returns all matching ecosystems for deb' do
    ecosystems = Ecosystem::Base.purl_type_to_ecosystems('deb')
    assert_includes ecosystems, 'debian'
    assert_includes ecosystems, 'ubuntu'
    assert_includes ecosystems, 'deb'
  end

  test 'purl_type_to_ecosystems returns single for npm' do
    assert_equal ['npm'], Ecosystem::Base.purl_type_to_ecosystems('npm')
  end

  test 'purl_type_to_ecosystem still returns first match' do
    assert_equal 'npm', Ecosystem::Base.purl_type_to_ecosystem('npm')
    refute_nil Ecosystem::Base.purl_type_to_ecosystem('deb')
  end

  test 'purl_type_namespace_in_name? defaults true for unknown types' do
    assert Ecosystem::Base.purl_type_namespace_in_name?('totally-unknown')
  end

  test 'download_and_cache returns cached file when it exists and is fresh' do
    cache_dir = Rails.root.join('tmp', 'cache', 'ecosystems')
    FileUtils.mkdir_p(cache_dir)
    cached_file = cache_dir.join('test-cache-fresh')
    File.write(cached_file, 'test content')

    result = @ecosystem.download_and_cache('https://example.com/file.txt', 'test-cache-fresh', ttl: 1.hour)

    assert_equal cached_file, result
    assert cached_file.exist?
    FileUtils.rm_f(cached_file)
  end
end
