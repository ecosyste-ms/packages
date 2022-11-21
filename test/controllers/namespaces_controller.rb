require 'test_helper'

class NamespacesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(name: 'rand', ecosystem: @registry.ecosystem, namespace: 'foo')
    @version = @package.versions.create(number: '0.1.0', published_at: Time.now)
  end

  test 'list namespaces for a registry' do
    get registry_namespaces_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'namespaces/index', file: 'namespaces/index.json.jbuilder'
  end

  test 'get a namespace for a registry' do
    get registry_namespace_path(registry_id: @registry.name, id: 'foo')
    assert_response :success
    assert_template 'namespaces/show', file: 'namespaces/show.json.jbuilder'
  end
end