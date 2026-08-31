require "test_helper"

class DockerQuayTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(name: 'quay.io', url: 'https://quay.io', ecosystem: 'docker', default: false)
    @ecosystem = @registry.ecosystem_instance
    @package = Package.new(ecosystem: 'docker', name: 'jupyter/scipy-notebook')
  end

  test 'ecosystem_instance is Quay' do
    assert_instance_of Ecosystem::Docker::Quay, @ecosystem
  end

  test 'registry_url' do
    assert_equal 'https://quay.io/repository/jupyter/scipy-notebook', @ecosystem.registry_url(@package)
  end

  test 'check_status_url' do
    assert_equal 'https://quay.io/api/v1/repository/jupyter/scipy-notebook?includeTags=false', @ecosystem.check_status_url(@package)
  end

  test 'install_command' do
    assert_equal 'docker pull quay.io/jupyter/scipy-notebook', @ecosystem.install_command(@package)
    assert_equal 'docker pull quay.io/jupyter/scipy-notebook:latest', @ecosystem.install_command(@package, 'latest')
  end

  test 'package_metadata' do
    stub_request(:get, "https://quay.io/api/v1/repository/jupyter/scipy-notebook?includeTags=false&includeStats=true")
      .to_return(status: 200, body: file_fixture('docker/quay/scipy-notebook.json'), headers: { 'content-type' => 'application/json' })
    pkg = @ecosystem.package_metadata('jupyter/scipy-notebook')

    assert_equal 'jupyter/scipy-notebook', pkg[:name]
    assert_equal 'jupyter', pkg[:namespace]
    assert_match(/Jupyter/, pkg[:description])
    assert_equal 'https://github.com/jupyter/docker-stacks', pkg[:repository_url]
    assert pkg[:downloads] > 0
    assert_equal 'last-90-days', pkg[:downloads_period]
    assert_nil pkg[:status]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://quay.io/api/v1/repository/jupyter/scipy-notebook/tag/?limit=100&onlyActiveTags=true&page=1")
      .to_return(status: 200, body: file_fixture('docker/quay/scipy-notebook-tags.json'), headers: { 'content-type' => 'application/json' })
    versions = @ecosystem.versions_metadata(name: 'jupyter/scipy-notebook')

    assert_equal 3, versions.length
    v = versions.first
    assert v[:number].present?
    assert v[:published_at].present?
    assert v[:metadata][:digest].start_with?('sha256:')
  end

  test 'namespace_package_names paginates via next_page cursor' do
    stub_request(:get, "https://quay.io/api/v1/repository?public=true&namespace=foo")
      .to_return(status: 200, body: '{"repositories":[{"namespace":"foo","name":"a"}],"next_page":"CUR"}', headers: { 'content-type' => 'application/json' })
    stub_request(:get, "https://quay.io/api/v1/repository?public=true&namespace=foo&next_page=CUR")
      .to_return(status: 200, body: '{"repositories":[{"namespace":"foo","name":"b"}]}', headers: { 'content-type' => 'application/json' })

    assert_equal ['foo/a', 'foo/b'], @ecosystem.namespace_package_names('foo')
  end
end
