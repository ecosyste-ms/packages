require "test_helper"

class LeanTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'reservoir.lean-lang.org', url: 'https://reservoir.lean-lang.org', ecosystem: 'lean')
    @ecosystem = Ecosystem::Lean.new(@registry)
    @package = Package.new(ecosystem: 'lean', name: 'leanprover-community/mathlib', repository_url: 'https://github.com/leanprover-community/mathlib4', metadata: { 'default_branch' => 'master' })
    @version = @package.versions.build(number: '7e1d43ce0de119bf21df45cee606d4a9468e7989')
  end

  test 'registry_url' do
    assert_equal 'https://reservoir.lean-lang.org/@leanprover-community/mathlib', @ecosystem.registry_url(@package)
  end

  test 'install_command' do
    assert_nil @ecosystem.install_command(@package)
  end

  test 'download_url' do
    assert_equal 'https://codeload.github.com/leanprover-community/mathlib4/tar.gz/7e1d43ce0de119bf21df45cee606d4a9468e7989', @ecosystem.download_url(@package, @version)
  end

  test 'download_url without version uses default branch' do
    assert_equal 'https://codeload.github.com/leanprover-community/mathlib4/tar.gz/refs/heads/master', @ecosystem.download_url(@package, nil)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:lean/leanprover-community/mathlib', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:lean/leanprover-community/mathlib@7e1d43ce0de119bf21df45cee606d4a9468e7989', purl
    assert Purl.parse(purl)
  end

  test 'check_status_url' do
    assert_equal 'https://reservoir.lean-lang.org/@leanprover-community/mathlib', @ecosystem.check_status_url(@package)
  end

  test 'sync_in_batches' do
    assert @ecosystem.sync_in_batches?
  end

  test 'all_package_names' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    all_package_names = @ecosystem.all_package_names
    assert_equal 2, all_package_names.length
    assert_includes all_package_names, 'leanprover-community/mathlib'
    assert_includes all_package_names, 'leanprover-community/aesop'
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    names = @ecosystem.recently_updated_package_names
    assert_equal 2, names.length
    assert_equal 'leanprover-community/mathlib', names.first
  end

  test 'namespace_package_names' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    names = @ecosystem.namespace_package_names('leanprover-community')
    assert_equal 2, names.length
  end

  test 'package_metadata' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    package_metadata = @ecosystem.package_metadata('leanprover-community/mathlib')

    assert_equal 'leanprover-community/mathlib', package_metadata[:name]
    assert_equal 'The math library of Lean 4', package_metadata[:description]
    assert_equal 'https://leanprover-community.github.io/mathlib4_docs', package_metadata[:homepage]
    assert_equal 'Apache-2.0', package_metadata[:licenses]
    assert_equal 'https://github.com/leanprover-community/mathlib4', package_metadata[:repository_url]
    assert_equal 'leanprover-community', package_metadata[:namespace]
    assert_equal 'master', package_metadata[:metadata][:default_branch]
  end

  test 'versions_metadata' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    package_metadata = @ecosystem.package_metadata('leanprover-community/mathlib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal 2, versions_metadata.length
    assert_equal '7e1d43ce0de119bf21df45cee606d4a9468e7989', versions_metadata.first[:number]
    assert_equal '0.0.0', versions_metadata.first[:metadata][:version]
    assert_equal 'leanprover/lean4:v4.30.0-rc2', versions_metadata.first[:metadata][:toolchain]
    assert versions_metadata.first[:published_at].present?
  end

  test 'dependencies_metadata' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    package_metadata = @ecosystem.package_metadata('leanprover-community/mathlib')
    deps = @ecosystem.dependencies_metadata('leanprover-community/mathlib', '7e1d43ce0de119bf21df45cee606d4a9468e7989', package_metadata)

    assert deps.length > 0
    dep_names = deps.map { |d| d[:package_name] }
    assert_includes dep_names, 'leanprover-community/aesop'
    refute_includes dep_names, 'leanprover/Cli'
    deps.each do |dep|
      assert_equal 'runtime', dep[:kind]
      assert_equal 'lean', dep[:ecosystem]
    end
  end

  test 'check_status removed when not in manifest' do
    stub_request(:get, "https://reservoir.lean-lang.org/index/manifest.json")
      .to_return({ status: 200, body: file_fixture('lean/manifest.json') })
    missing = Package.new(ecosystem: 'lean', name: 'foo/bar')
    assert_equal 'removed', @ecosystem.check_status(missing)
    assert_nil @ecosystem.check_status(@package)
  end
end
