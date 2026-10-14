require 'test_helper'

class ApiV1GoLookupTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create!(name: 'proxy.golang.org', url: 'https://proxy.golang.org', ecosystem: 'go', default: true)
  end

  test 'returned Go PURLs preserve case and resolve to the original package' do
    ['github.com/Masterminds/semver/v3', 'example.com/Owner/Module'].each do |name|
      package = @registry.packages.create!(ecosystem: 'go', name: name)
      @registry.packages.create!(ecosystem: 'go', name: name.downcase)
      @registry.packages.create!(ecosystem: 'go', name: name.gsub(/[A-Z]/) { |letter| "!#{letter.downcase}" })

      get lookup_api_v1_packages_path, params: { purl: "pkg:golang/#{name}" }

      assert_response :success
      result = Oj.load(response.body)
      assert_equal [package.id], result.pluck('id')
      assert_equal "pkg:golang/#{name}", result.first['purl']

      get lookup_api_v1_packages_path, params: { purl: result.first['purl'] }

      assert_response :success
      assert_equal [package.id], Oj.load(response.body).pluck('id')

      post bulk_lookup_api_v1_packages_path, params: { purls: [result.first['purl']] }

      assert_response :success
      assert_equal [package.id], Oj.load(response.body).pluck('id')
    end
  end

  test 'latest Go version preserves case in its PURL and escapes its download URL' do
    package = @registry.packages.create!(ecosystem: 'go', name: 'github.com/Masterminds/glide')
    version = package.versions.create!(number: 'v0.13.3')

    get latest_version_api_v1_registry_package_path(registry_id: @registry.name, id: package.name)

    assert_response :success
    result = Oj.load(response.body)
    assert_equal version.id, result['id']
    assert_equal 'pkg:golang/github.com/Masterminds/glide@v0.13.3', result['purl']
    assert_includes result['download_url'], '/github.com/!masterminds/glide/@v/v0.13.3.zip'
  end
end
