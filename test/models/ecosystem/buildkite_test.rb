require "test_helper"

class BuildkiteTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Buildkite Plugins', url: 'https://buildkite.com/resources/plugins', ecosystem: 'Buildkite')
    @ecosystem = Ecosystem::Buildkite.new(@registry)
    @package = Package.new(ecosystem: 'Buildkite', name: 'chronotc/monorepo-diff')
    @version = @package.versions.build(number: 'v2.4.0', metadata: { 'download_url' => 'https://codeload.github.com/chronotc/monorepo-diff-buildkite-plugin/tar.gz/v2.4.0' })
  end

  test 'purl_params use buildkite type and namespace' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:buildkite/chronotc/monorepo-diff', purl
  end

  test 'registry_url' do
    assert_equal 'https://buildkite.com/resources/plugins/chronotc-monorepo-diff', @ecosystem.registry_url(@package)
  end

  test 'repository based urls' do
    assert_equal 'https://github.com/chronotc/monorepo-diff-buildkite-plugin', @ecosystem.documentation_url(@package)
    assert_equal 'https://codeload.github.com/chronotc/monorepo-diff-buildkite-plugin/tar.gz/v2.4.0', @ecosystem.download_url(@package, @version)
    assert_equal 'https://github.com/chronotc/monorepo-diff-buildkite-plugin', @ecosystem.check_status_url(@package)
  end

  test 'install_command' do
    assert_equal "plugins:\n  - chronotc/monorepo-diff#v2.4.0: ~", @ecosystem.install_command(@package, @version)
  end

  test 'package_find_names includes repository form' do
    assert_equal ['chronotc/monorepo-diff', 'chronotc/monorepo-diff-buildkite-plugin'], @ecosystem.package_find_names('chronotc/monorepo-diff')
  end

  test 'fetch_package_metadata looks up canonical github repository' do
    stub_request(:get, 'https://repos.ecosyste.ms/api/v1/repositories/lookup?url=https%3A%2F%2Fgithub.com%2Fchronotc%2Fmonorepo-diff-buildkite-plugin')
      .to_return(status: 200, body: {
        full_name: 'chronotc/monorepo-diff-buildkite-plugin',
        owner: 'chronotc',
        description: 'Detect changed paths in a monorepo',
        license: 'MIT',
        topics: ['buildkite-plugin'],
        homepage: 'https://github.com/chronotc/monorepo-diff-buildkite-plugin',
        tags_url: 'https://repos.ecosyste.ms/api/v1/hosts/GitHub/repositories/chronotc%2Fmonorepo-diff-buildkite-plugin/tags',
        default_branch: 'main'
      }.to_json, headers: { 'Content-Type' => 'application/json' })

    metadata = @ecosystem.package_metadata('chronotc/monorepo-diff')

    assert_equal 'chronotc/monorepo-diff', metadata[:name]
    assert_equal 'https://github.com/chronotc/monorepo-diff-buildkite-plugin', metadata[:repository_url]
    assert_equal 'MIT', metadata[:licenses]
    assert_equal 'chronotc', metadata[:namespace]
  end
end
