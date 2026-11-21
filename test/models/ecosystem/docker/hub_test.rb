require "test_helper"

class DockerHubTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'hub.docker.com', url: 'https://hub.docker.com', ecosystem: 'docker', default: true)
    @ecosystem = @registry.ecosystem_instance
    @package = Package.new(ecosystem: 'docker', name: 'library/alpine')
  end

  test 'ecosystem_instance is Hub' do
    assert_instance_of Ecosystem::Docker::Hub, @ecosystem
  end

  test 'registry_url' do
    assert_equal 'https://hub.docker.com/r/library/alpine', @ecosystem.registry_url(@package)
  end

  test 'check_status_url' do
    assert_equal 'https://hub.docker.com/v2/repositories/library/alpine', @ecosystem.check_status_url(@package)
  end

  test 'install_command has no host prefix for default registry' do
    assert_equal 'docker pull library/alpine', @ecosystem.install_command(@package)
    assert_equal 'docker pull library/alpine:3.19', @ecosystem.install_command(@package, '3.19')
  end

  test 'purl' do
    assert_equal 'pkg:docker/library%2Falpine', @ecosystem.purl(@package)
  end

  test 'map_package_metadata' do
    @ecosystem.stubs(:load_repository_url).returns('https://github.com/docker-library/official-images')
    pkg = { 'namespace' => 'library', 'name' => 'alpine', 'description' => 'small', 'pull_count' => 42 }
    mapped = @ecosystem.map_package_metadata(pkg)

    assert_equal 'library/alpine', mapped[:name]
    assert_equal 'library', mapped[:namespace]
    assert_equal 'small', mapped[:description]
    assert_equal 42, mapped[:downloads]
    assert_equal 'total', mapped[:downloads_period]
    assert_equal 'https://github.com/docker-library/official-images', mapped[:repository_url]
  end
end
