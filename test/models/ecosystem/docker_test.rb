require "test_helper"

class DockerTest < ActiveSupport::TestCase
  setup do
    @hub = Registry.new(name: 'hub.docker.com', url: 'https://hub.docker.com', ecosystem: 'docker', default: true)
    @quay = Registry.new(name: 'quay.io', url: 'https://quay.io', ecosystem: 'docker', default: false)
    @ghcr = Registry.new(name: 'ghcr.io', url: 'https://ghcr.io', ecosystem: 'docker', default: false)
  end

  test 'for_registry dispatches to subclass by host' do
    assert_equal Ecosystem::Docker::Hub, @hub.ecosystem_class
    assert_equal Ecosystem::Docker::Quay, @quay.ecosystem_class
    assert_equal Ecosystem::Docker, @ghcr.ecosystem_class
  end

  test 'subclasses are not in Base.list' do
    names = Ecosystem::Base.list.map(&:name)
    assert_includes names, 'Ecosystem::Docker'
    refute_includes names, 'Ecosystem::Docker::Hub'
    refute_includes names, 'Ecosystem::Docker::Quay'
  end

  test 'purl_type is docker for all subclasses' do
    assert_equal 'docker', Ecosystem::Docker.purl_type
    assert_equal 'docker', Ecosystem::Docker::Hub.purl_type
    assert_equal 'docker', Ecosystem::Docker::Quay.purl_type
  end

  test 'install_command prefixes registry host unless default' do
    pkg = Package.new(name: 'foo/bar')
    assert_equal 'docker pull foo/bar:1.0', @hub.ecosystem_instance.install_command(pkg, '1.0')
    assert_equal 'docker pull quay.io/foo/bar:1.0', @quay.ecosystem_instance.install_command(pkg, '1.0')
    assert_equal 'docker pull ghcr.io/foo/bar:1.0', @ghcr.ecosystem_instance.install_command(pkg, '1.0')
  end

  test 'purl includes repository_url qualifier for non-default registry' do
    pkg = Package.new(name: 'foo/bar')
    assert_equal 'pkg:docker/foo%2Fbar', @hub.ecosystem_instance.purl(pkg)
    assert_match %r{^pkg:docker/foo%2Fbar\?repository_url=.*quay\.io}, @quay.ecosystem_instance.purl(pkg)
  end

  test 'v2 base fetches tags with anonymous token flow' do
    eco = @ghcr.ecosystem_instance
    stub_request(:get, "https://ghcr.io/v2/foo/bar/tags/list?n=1000")
      .to_return(status: 401, headers: { 'www-authenticate' => 'Bearer realm="https://ghcr.io/token",service="ghcr.io",scope="repository:foo/bar:pull"' })
    stub_request(:get, "https://ghcr.io/token?scope=repository:foo/bar:pull&service=ghcr.io")
      .to_return(status: 200, body: '{"token":"abc"}', headers: { 'content-type' => 'application/json' })
    stub_request(:get, "https://ghcr.io/v2/foo/bar/tags/list?n=1000")
      .with(headers: { 'Authorization' => 'Bearer abc' })
      .to_return(status: 200, body: '{"name":"foo/bar","tags":["1.0","1.1"]}', headers: {})

    pkg = eco.package_metadata('foo/bar')
    assert_equal 'foo/bar', pkg[:name]
    assert_equal 'foo', pkg[:namespace]
    assert_equal ['1.0', '1.1'], pkg[:tags]

    versions = eco.versions_metadata(pkg)
    assert_equal [{ number: '1.0' }, { number: '1.1' }], versions
  end

  test 'v2 base without auth challenge' do
    eco = @quay.ecosystem_instance
    stub_request(:get, "https://quay.io/v2/foo/bar/tags/list?n=1000")
      .to_return(status: 200, body: '{"name":"foo/bar","tags":["a","b"]}', headers: {})
    assert_equal ['a', 'b'], eco.v2_tags('foo/bar')
  end

  test 'v2_tags follows Link pagination' do
    eco = Ecosystem::Docker.new(@ghcr)
    stub_request(:get, "https://ghcr.io/v2/foo/bar/tags/list?n=1000")
      .to_return(status: 200, body: '{"tags":["a"]}', headers: { 'link' => '</v2/foo/bar/tags/list?n=1000&last=a>; rel="next"' })
    stub_request(:get, "https://ghcr.io/v2/foo/bar/tags/list?n=1000&last=a")
      .to_return(status: 200, body: '{"tags":["b"]}', headers: {})
    assert_equal ['a', 'b'], eco.v2_tags('foo/bar')
  end

  test 'v2_tags follows absolute Link URL' do
    eco = Ecosystem::Docker.new(@ghcr)
    stub_request(:get, "https://ghcr.io/v2/foo/bar/tags/list?n=1000")
      .to_return(status: 200, body: '{"tags":["a"]}', headers: { 'link' => '<https://ghcr.io/v2/foo/bar/tags/list?n=1000&last=a>; rel="next"' })
    stub_request(:get, "https://ghcr.io/v2/foo/bar/tags/list?n=1000&last=a")
      .to_return(status: 200, body: '{"tags":["b"]}', headers: {})
    assert_equal ['a', 'b'], eco.v2_tags('foo/bar')
  end

  test 'check_status marks removed when token flow yields 404' do
    eco = @ghcr.ecosystem_instance
    eco.stubs(:fetch_package_metadata).returns(nil)
    stub_request(:get, "https://ghcr.io/v2/foo/gone/tags/list")
      .to_return(status: 401, headers: { 'www-authenticate' => 'Bearer realm="https://ghcr.io/token",service="ghcr.io",scope="repository:foo/gone:pull"' })
    stub_request(:get, "https://ghcr.io/token?scope=repository:foo/gone:pull&service=ghcr.io")
      .to_return(status: 200, body: '{"token":"abc"}', headers: { 'content-type' => 'application/json' })
    stub_request(:get, "https://ghcr.io/v2/foo/gone/tags/list")
      .with(headers: { 'Authorization' => 'Bearer abc' })
      .to_return(status: 404, body: '{"errors":[{"code":"NAME_UNKNOWN"}]}')

    assert_equal 'removed', eco.check_status(Package.new(name: 'foo/gone'))
  end
end
