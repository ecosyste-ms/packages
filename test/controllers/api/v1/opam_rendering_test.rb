require 'test_helper'

class OpamRenderingTest < ActionDispatch::IntegrationTest
  test 'package and version JSON render current and archived opam metadata without network requests' do
    registry = Registry.create!(name: 'opam.ocaml.org', url: 'https://opam.ocaml.org', ecosystem: 'opam', default: true)
    package = registry.packages.create!(name: 'lwt', ecosystem: 'opam', metadata: { archived: false })
    current = package.versions.create!(number: '6.1.2', registry: registry, metadata: {
      archived: false, download_url: 'https://github.com/ocsigen/lwt/archive/refs/tags/6.1.2.tar.gz'
    })
    archived = package.versions.create!(number: '4.1.0', registry: registry, metadata: {
      archived: true, download_url: 'https://github.com/ocsigen/lwt/archive/4.1.0.tar.gz'
    })
    package.versions.create!(number: '4.0.0', registry: registry, metadata: { archived: true })
    Ecosystem::Opam.any_instance.expects(:request).never
    Ecosystem::Opam.any_instance.expects(:graphql).never
    Ecosystem::Opam.any_instance.expects(:archive_index).never

    get api_v1_registry_package_path(registry_id: registry.name, id: package.name)
    assert_response :success
    assert_equal 'https://opam.ocaml.org/packages/lwt/', response.parsed_body['registry_url']

    get api_v1_registry_package_versions_path(registry_id: registry.name, package_id: package.name)
    assert_response :success
    versions = response.parsed_body.index_by { |entry| entry['number'] }
    assert_equal current.metadata['download_url'], versions.fetch(current.number)['download_url']
    assert_equal archived.metadata['download_url'], versions.fetch(archived.number)['download_url']
    assert_nil versions.fetch('4.0.0')['download_url']
    assert_equal true, versions.fetch(archived.number).dig('metadata', 'archived')
    assert_includes versions.fetch(archived.number)['registry_url'], 'opam-repository-archive/blob/main'

    get api_v1_registry_package_version_path(registry_id: registry.name, package_id: package.name, id: archived.number)
    assert_response :success
    assert_nil response.parsed_body['documentation_url']
    assert_includes response.parsed_body['install_command'], 'opam repository add archive'

    get latest_version_api_v1_registry_package_path(registry_id: registry.name, id: package.name)
    assert_response :success
    assert_equal current.number, response.parsed_body['number']

    package.update!(metadata: { archived: true })
    get api_v1_registry_package_path(registry_id: registry.name, id: package.name)
    assert_response :success
    assert_equal 'https://github.com/ocaml/opam-repository-archive/tree/main/packages/lwt', response.parsed_body['registry_url']
    assert_not_requested :any, /.*/
  end
end
