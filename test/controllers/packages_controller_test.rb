require 'test_helper'

class PackagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @registry = Registry.create(name: 'crates.io', url: 'https://crates.io', ecosystem: 'cargo')
    @package = @registry.packages.create(ecosystem: 'cargo', name: 'rand', metadata: {foo: 'bar'})
  end

  test 'list packages for a registry' do
    get registry_packages_path(registry_id: @registry.name)
    assert_response :success
    assert_template 'packages/index', file: 'packages/index.html.erb'
  end

  test 'get a package for a registry' do
    get registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_template 'packages/show', file: 'packages/show.html.erb'
  end

  test 'package name with path traversal segments returns 404' do
    # A package named "./../../../" generates a URL that CDNs normalise to "/",
    # so serving it as 200 with public cache headers poisons the homepage cache.
    # Such names are rejected at validation time; if one already exists in the
    # database the show action must still refuse to serve it.
    package = @registry.packages.build(ecosystem: 'cargo', name: './../../../')
    package.save(validate: false)

    get '/registries/crates.io/packages/.%2F..%2F..%2F..%2F'
    assert_response :not_found
  end

  test 'path traversal segments in any glob route param return 404' do
    # These routes render 200 for arbitrary ids, so without this guard a
    # request like /registries/crates.io/namespaces/..%2F..%2F.. would be
    # cached by the CDN under "/".
    [
      '/keywords/..',
      '/registries/crates.io/namespaces/..%2F..%2F..',
      '/registries/crates.io/keywords/..%2F..%2F..',
      '/registries/crates.io/maintainers/..%2F..%2F..',
      '/registries/crates.io/packages/rand/versions/..',
      '/api/v1/registries/crates.io/packages/..%2F..%2F..%2F..',
      '/api/v1/keywords/..%2F..',
    ].each do |path|
      get path
      assert_response :not_found, "expected 404 for #{path}"
    end
  end

  test 'list packages for a nixpkgs registry' do
    nix_registry = Registry.create(name: 'nixpkgs-23.05', url: 'https://channels.nixos.org/nixos-23.05', ecosystem: 'nixpkgs', version: '23.05')
    nix_registry.packages.create(ecosystem: 'nixpkgs', name: 'python313Packages.numpy', metadata: { 'position' => 'pkgs/development/python-modules/numpy/2.nix:205' })

    get registry_packages_path(registry_id: nix_registry.name)
    assert_response :success
    assert_template 'packages/index', file: 'packages/index.html.erb'
  end

  test 'get a package with nil keywords should not error' do
    package = @registry.packages.create(ecosystem: 'cargo', name: 'test-package', keywords: nil)
    get registry_package_path(registry_id: @registry.name, id: package.name)
    assert_response :success
    assert_template 'packages/show', file: 'packages/show.html.erb'
  end

  test 'get pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get dependent_packages for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get dependent_packages_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'dependent_packages serves from top_dependent_packages cache when available' do
    dep1 = @registry.packages.create(name: 'dep-one', ecosystem: @registry.ecosystem)
    dep2 = @registry.packages.create(name: 'dep-two', ecosystem: @registry.ecosystem)
    TopDependentPackage.create!(package_id: @package.id, sort: 'downloads', dependent_ids: [dep2.id, dep1.id], updated_at: Time.current)

    get dependent_packages_registry_package_path(registry_id: @registry.name, id: @package.name, sort: 'downloads', order: 'desc')
    assert_response :success
    assert_template 'packages/dependent_packages'
    assert_equal [dep2, dep1], assigns(:dependent_packages)
  end

  test 'dependent_packages skips kinds sidebar above threshold' do
    @package.update_column(:dependent_packages_count, TopDependentPackage::THRESHOLD + 1)

    get dependent_packages_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_nil assigns(:kinds)
    assert_no_match 'Filter by Kind', @response.body
  end

  test 'dependent_packages renders kinds sidebar below threshold' do
    dependent = @registry.packages.create(name: 'needs-rand', ecosystem: @registry.ecosystem)
    v = dependent.versions.create(number: '1.0.0', latest: true)
    v.dependencies.create(package_id: @package.id, package_name: @package.name, ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')

    get dependent_packages_registry_package_path(registry_id: @registry.name, id: @package.name)
    assert_response :success
    assert_equal({ 'runtime' => 1 }, assigns(:kinds))
    assert_match 'Filter by Kind', @response.body
  end

  test 'dependent_packages falls through when no cache row exists' do
    dependent = @registry.packages.create(name: 'needs-rand', ecosystem: @registry.ecosystem)
    v = dependent.versions.create(number: '1.0.0', latest: true)
    v.dependencies.create(package_id: @package.id, package_name: @package.name, ecosystem: @registry.ecosystem, requirements: '>= 0', kind: 'runtime')

    get dependent_packages_registry_package_path(registry_id: @registry.name, id: @package.name, sort: 'downloads')
    assert_response :success
    assert_equal [dependent], assigns(:dependent_packages)
  end

  test 'get maintainers for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get maintainers_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get related_packages for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get related_packages_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end

  test 'get advisories for pypi package with underscore in name' do
    pypi_registry = Registry.create(name: 'pypi.org', url: 'https://pypi.org', ecosystem: 'pypi')
    pypi_package = pypi_registry.packages.create(
      ecosystem: 'pypi',
      name: 'tomli-w',
      metadata: { 'normalized_name' => 'tomli-w' }
    )

    get advisories_registry_package_path(registry_id: pypi_registry.name, id: 'tomli_w')
    assert_response :success
  end
end