require 'test_helper'

class ApiV1VersionAdvisoriesTest < ActionDispatch::IntegrationTest
  CASES = [
    ['npm', '>=1.0.0,<2.0.0', { '1.0.0-alpha.1' => false, '1.0.0' => true, '1.7.0-alpha.2' => true, '2.0.0-alpha.1' => true, '2.0.0' => false }],
    ['npm', '>= 1.0.0, < 2.0.0 || >= 3.0.0, < 4.0.0', { '1.5.0' => true, '2.5.0' => false, '3.5.0' => true, '4.0.0' => false }],
    ['npm', '>= 1.0.0, < 2.0.0', { '0.9.0' => false, '1.0.0' => true, '1.5.0' => true, '2.0.0' => false }],
    ['npm', '>= 9.0.0, < 9.5.4', { '9.5.3' => true, '9.5.4' => false, '10.0.0-beta.0' => false }, '@astrojs/node'],
    ['npm', '< 10.0.0', { '9.5.3' => true, '10.0.0-beta.0' => true, '10.0.0' => false }, '@astrojs/node'],
    ['cargo', '>= 2.1.0, < 2.41.0', { '2.0.0' => false, '2.1.0' => true, '2.15.1-beta.0' => true, '2.40.0' => true, '2.41.0' => false }, 'static-web-server'],
    ['npm', '< 3.0.0', { '1.7.0-alpha.2' => true, '1.7.0' => true, '3.0.0' => false, '3.1.0-alpha.1' => false }],
    ['cargo', '< 3.0.0', { '1.7.0-alpha.2' => true, '1.7.0' => true, '3.0.0' => false, '3.1.0-alpha.1' => false }],
    ['packagist', '^1.0', { '0.9.0' => false, '1.0.0' => true, '1.2.3' => true, '2.0.0' => false }]
  ].freeze

  CASES.each_with_index do |(ecosystem, range, candidates, package_name), index|
    test "version API matches #{ecosystem} advisory range #{index}" do
      registry = Registry.create!(name: "#{ecosystem}.example", url: "https://#{ecosystem}.example", ecosystem: ecosystem)
      name = package_name || (ecosystem == 'packagist' ? 'vendor/widget' : 'widget')
      package = registry.packages.create!(name: name, ecosystem: ecosystem, advisories: [{
        'uuid' => 'advisory-range-test',
        'identifiers' => [],
        'packages' => [{
          'ecosystem' => ecosystem,
          'package_name' => name,
          'versions' => [{ 'vulnerable_version_range' => range }]
        }]
      }])

      candidates.each do |number, affected|
        package.versions.create!(number: number, registry: registry)
        get api_v1_registry_package_version_path(registry_id: registry.name, package_id: name, id: number)

        assert_response :success
        expected = affected ? ['advisory-range-test'] : []
        assert_equal expected, response.parsed_body.fetch('advisories').pluck('uuid'), "#{number} in #{range}"
      end

      get api_v1_registry_package_versions_path(registry_id: registry.name, package_id: name)
      assert_response :success
      affected_numbers = response.parsed_body.select { |version| version.fetch('advisories').any? }.pluck('number')
      assert_equal candidates.select { |_, affected| affected }.keys.sort, affected_numbers.sort
    end
  end
end
