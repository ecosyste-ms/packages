require "test_helper"

class OpenapiTest < ActiveSupport::TestCase
  test 'openapi.yaml is valid' do
    f = YAML.load_file(Rails.root.join('openapi/api/v1/openapi.yaml'))
    assert_equal f.class, Hash
  end

  test 'openapi.yaml documents artifact endpoints' do
    document = YAML.load_file(Rails.root.join('openapi/api/v1/openapi.yaml'))

    assert document.dig('paths', '/artifacts/lookup')
    assert document.dig('paths', '/artifacts/{artifactId}')
    assert document.dig('paths', '/registries/{registryName}/packages/{packageName}/versions/{versionNumber}/artifacts')
    assert document.dig('components', 'schemas', 'Artifact')
    assert document.dig('components', 'schemas', 'ArtifactLookup')

    lookup = document.dig('paths', '/artifacts/lookup', 'get')
    assert_includes lookup['description'], 'integrity, sha256, sha1, or sha512'
    assert_equal %w[200 400], lookup.fetch('responses').keys

    nested = document.dig('paths', '/registries/{registryName}/packages/{packageName}/versions/{versionNumber}/artifacts', 'get')
    assert_equal %w[200 404], nested.fetch('responses').keys
  end

  test 'openapi operation ids are unique' do
    document = YAML.load_file(Rails.root.join('openapi/api/v1/openapi.yaml'))
    operation_ids = document.fetch('paths').values.flat_map do |path|
      path.values.filter_map do |operation|
        operation['operationId'] if operation.is_a?(Hash)
      end
    end

    assert_equal operation_ids.uniq, operation_ids
  end
end
