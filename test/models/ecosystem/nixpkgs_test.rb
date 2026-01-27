require "test_helper"

class NixpkgsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'nixpkgs-unstable', url: 'https://channels.nixos.org/nixos-unstable', ecosystem: 'nixpkgs', version: 'unstable')
    @ecosystem = Ecosystem::Nixpkgs.new(@registry)
    @package = Package.new(ecosystem: 'nixpkgs', name: 'numpy', metadata: { 'position' => 'pkgs/development/python-modules/numpy/2.nix:205' })
    @version = @package.versions.build(number: '2.3.5')
    Ecosystem::Nixpkgs.clear_packages_cache!
  end

  teardown do
    Ecosystem::Nixpkgs.clear_packages_cache!
  end

  def stub_packages(packages)
    Ecosystem::Nixpkgs.class_variable_set(:@@packages_cache, { 'unstable' => packages })
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://search.nixos.org/packages?channel=unstable&query=numpy'
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_equal registry_url, 'https://search.nixos.org/packages?channel=unstable&query=numpy'
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_equal documentation_url, 'https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/development/python-modules/numpy/2.nix#L205'
  end

  test 'documentation_url without position' do
    package = Package.new(ecosystem: 'nixpkgs', name: 'test')
    documentation_url = @ecosystem.documentation_url(package)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'nix-env -iA nixpkgs.numpy'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, 'nix-env -iA nixpkgs.numpy'
  end

  test 'check_status_url' do
    check_status_url = @ecosystem.check_status_url(@package)
    assert_equal check_status_url, 'https://search.nixos.org/packages?channel=unstable&query=numpy'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:nix/numpy?channel=unstable'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:nix/numpy@2.3.5?channel=unstable'
    assert Purl.parse(purl)
  end

  test 'purl for non-default registry' do
    registry = Registry.new(default: false, name: 'nixpkgs-24.11', url: 'https://channels.nixos.org/nixos-24.11', ecosystem: 'nixpkgs', version: '24.11')
    ecosystem = Ecosystem::Nixpkgs.new(registry)
    purl = ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:nix/numpy@2.3.5?channel=24.11&repository_url=https://channels.nixos.org/nixos-24.11'
    assert Purl.parse(purl)
  end

  test 'map_package_metadata' do
    raw_metadata = {
      'pname' => 'numpy',
      'version' => '2.3.5',
      'name' => 'python3.13-numpy-2.3.5',
      'system' => 'x86_64-linux',
      'outputs' => { 'out' => nil, 'dist' => nil },
      'meta' => {
        'description' => 'Scientific tools for Python',
        'homepage' => 'https://numpy.org/',
        'license' => {
          'spdxId' => 'BSD-3-Clause',
          'shortName' => 'bsd3'
        },
        'position' => 'pkgs/development/python-modules/numpy/2.nix:205',
        'platforms' => ['x86_64-linux', 'aarch64-linux'],
        'maintainers' => [
          { 'name' => 'Doron Behar', 'github' => 'doronbehar', 'email' => 'me@doronbehar.com' }
        ],
        'isBuildPythonPackage' => ['x86_64-linux']
      }
    }

    # attribute_path is passed as second argument
    mapped = @ecosystem.map_package_metadata(raw_metadata, 'python313Packages.numpy')

    assert_equal mapped[:name], 'python313Packages.numpy'
    assert_equal mapped[:description], 'Scientific tools for Python'
    assert_equal mapped[:homepage], 'https://numpy.org/'
    assert_equal mapped[:licenses], 'BSD-3-Clause'
    assert_equal mapped[:metadata][:position], 'pkgs/development/python-modules/numpy/2.nix:205'
    assert_equal mapped[:metadata][:nix_attribute], 'python3.13-numpy-2.3.5'
    assert_includes mapped[:keywords_array], 'python'
  end

  test 'map_package_metadata with multiple licenses' do
    raw_metadata = {
      'pname' => 'test',
      'version' => '1.0',
      'meta' => {
        'license' => [
          { 'spdxId' => 'MIT' },
          { 'spdxId' => 'Apache-2.0' }
        ]
      }
    }

    mapped = @ecosystem.map_package_metadata(raw_metadata, 'test')
    assert_equal mapped[:licenses], 'MIT, Apache-2.0'
  end

  test 'map_package_metadata returns false for blank metadata' do
    assert_equal @ecosystem.map_package_metadata(nil, 'test'), false
    assert_equal @ecosystem.map_package_metadata({}, 'test'), false
    assert_equal @ecosystem.map_package_metadata({ 'pname' => nil }, 'test'), false
  end

  test 'versions_metadata' do
    stub_packages({
      'python313Packages.numpy' => {
        'pname' => 'numpy',
        'version' => '2.3.5',
        'name' => 'python3.13-numpy-2.3.5',
        'system' => 'x86_64-linux',
        'outputs' => { 'out' => nil },
        'meta' => {
          'license' => { 'spdxId' => 'BSD-3-Clause' }
        }
      }
    })

    versions = @ecosystem.versions_metadata({ name: 'python313Packages.numpy' })

    assert_equal versions.length, 1
    assert_equal versions[0][:number], '2.3.5'
    assert_equal versions[0][:licenses], 'BSD-3-Clause'
    assert_equal versions[0][:metadata][:nix_attribute], 'python3.13-numpy-2.3.5'
  end

  test 'maintainers_metadata' do
    stub_packages({
      'python313Packages.numpy' => {
        'pname' => 'numpy',
        'meta' => {
          'maintainers' => [
            { 'name' => 'Doron Behar', 'github' => 'doronbehar', 'email' => 'me@doronbehar.com' }
          ]
        }
      }
    })

    maintainers = @ecosystem.maintainers_metadata('python313Packages.numpy')

    assert_equal maintainers.length, 1
    assert_equal maintainers[0][:uuid], 'doronbehar'
    assert_equal maintainers[0][:name], 'Doron Behar'
    assert_equal maintainers[0][:email], 'me@doronbehar.com'
    assert_equal maintainers[0][:url], 'https://github.com/doronbehar'
  end

  test 'maintainers_metadata returns empty for missing maintainers' do
    stub_packages({
      'test' => { 'pname' => 'test', 'meta' => {} }
    })

    maintainers = @ecosystem.maintainers_metadata('test')
    assert_equal maintainers, []
  end

  test 'dependencies_metadata returns empty when no position' do
    stub_packages({
      'test-pkg' => { 'pname' => 'test', 'meta' => {} }
    })

    deps = @ecosystem.dependencies_metadata('test-pkg', '1.0', nil)
    assert_equal deps, []
  end

  test 'parse_nix_dependencies extracts dependencies from nix file' do
    nix_content = <<~NIX
      { lib, stdenv, fetchFromGitHub, blas, lapack, cython, gfortran, python3, hypothesis }:

      buildPythonPackage rec {
        pname = "numpy";
        version = "2.3.5";

        buildInputs = [ blas lapack ];

        nativeBuildInputs = [ cython gfortran ];

        nativeCheckInputs = [ hypothesis ];

        propagatedBuildInputs = [ python3 ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)

    # buildInputs -> runtime
    assert deps.any? { |d| d[:package_name] == 'blas' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'lapack' && d[:kind] == 'runtime' }

    # propagatedBuildInputs -> runtime
    assert deps.any? { |d| d[:package_name] == 'python3' && d[:kind] == 'runtime' }

    # nativeBuildInputs -> build
    assert deps.any? { |d| d[:package_name] == 'cython' && d[:kind] == 'build' }
    assert deps.any? { |d| d[:package_name] == 'gfortran' && d[:kind] == 'build' }

    # nativeCheckInputs -> test
    assert deps.any? { |d| d[:package_name] == 'hypothesis' && d[:kind] == 'test' }

    # Should not include builtins
    refute deps.any? { |d| d[:package_name] == 'lib' }
    refute deps.any? { |d| d[:package_name] == 'stdenv' }
    refute deps.any? { |d| d[:package_name] == 'fetchFromGitHub' }
  end

  test 'extract_nix_list handles multiline lists' do
    content = <<~NIX
      buildInputs = [
        blas
        lapack
        zlib
      ];
    NIX

    result = @ecosystem.extract_nix_list(content, 'buildInputs')
    assert_includes result, 'blas'
    assert_includes result, 'lapack'
    assert_includes result, 'zlib'
  end

  test 'extract_nix_list handles concatenation' do
    content = 'buildInputs = [ blas ] ++ optional stdenv.isDarwin [ accelerate ];'

    result = @ecosystem.extract_nix_list(content, 'buildInputs')
    assert_includes result, 'blas'
  end

  test 'nix_builtin? identifies stdlib functions' do
    assert @ecosystem.nix_builtin?('lib')
    assert @ecosystem.nix_builtin?('stdenv')
    assert @ecosystem.nix_builtin?('fetchFromGitHub')
    assert @ecosystem.nix_builtin?('mkDerivation')

    refute @ecosystem.nix_builtin?('numpy')
    refute @ecosystem.nix_builtin?('blas')
  end

  test 'extract_nix_list handles empty list' do
    content = 'buildInputs = [ ];'
    result = @ecosystem.extract_nix_list(content, 'buildInputs')
    assert_equal result, []
  end

  test 'extract_nix_list returns empty when attribute not found' do
    content = 'nativeBuildInputs = [ foo ];'
    result = @ecosystem.extract_nix_list(content, 'buildInputs')
    assert_equal result, []
  end

  test 'parse_nix_dependencies handles with syntax' do
    nix_content = <<~NIX
      { lib, python3Packages }:

      python3Packages.buildPythonPackage {
        buildInputs = with python3Packages; [ numpy scipy ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    # numpy and scipy aren't in the function args, so they won't be included
    # This is expected - we only track deps that are explicit function args
    assert_equal deps, []
  end

  test 'parse_nix_dependencies only includes deps from function args' do
    nix_content = <<~NIX
      { lib, stdenv, blas }:

      stdenv.mkDerivation {
        buildInputs = [ blas lapack ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    # Only blas is in function args, lapack is not
    assert deps.any? { |d| d[:package_name] == 'blas' }
    refute deps.any? { |d| d[:package_name] == 'lapack' }
  end

  test 'parse_nix_dependencies handles inherit syntax in args' do
    nix_content = <<~NIX
      { lib
      , stdenv
      , fetchFromGitHub
      , blas
      , lapack
      }:

      stdenv.mkDerivation {
        buildInputs = [ blas lapack ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    assert deps.any? { |d| d[:package_name] == 'blas' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'lapack' && d[:kind] == 'runtime' }
  end

  test 'parse_nix_dependencies handles comments' do
    nix_content = <<~NIX
      { lib, stdenv, blas, lapack }:
      # This is a comment
      stdenv.mkDerivation {
        buildInputs = [
          blas  # inline comment
          lapack
        ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    assert deps.any? { |d| d[:package_name] == 'blas' }
    assert deps.any? { |d| d[:package_name] == 'lapack' }
    dep_names = deps.map { |d| d[:package_name] }
    assert_not_includes dep_names, 'inline'
    assert_not_includes dep_names, 'comment'
    assert_not_includes dep_names, 'This'
  end

  test 'parse_nix_dependencies strips block comments' do
    nix_content = <<~NIX
      { lib, stdenv, blas, lapack }:
      stdenv.mkDerivation {
        buildInputs = [
          blas
          /* lapack is a circular dependency, not packaged */
        ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    dep_names = deps.map { |d| d[:package_name] }
    assert_includes dep_names, 'blas'
    assert_not_includes dep_names, 'circular'
    assert_not_includes dep_names, 'dependency'
    assert_not_includes dep_names, 'packaged'
  end

  test 'parse_nix_dependencies strips comments with words matching function args' do
    nix_content = <<~NIX
      { lib, stdenv, blas, round, building }:
      stdenv.mkDerivation {
        buildInputs = [
          blas
          # round and building are not real deps
        ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    dep_names = deps.map { |d| d[:package_name] }
    assert_includes dep_names, 'blas'
    assert_not_includes dep_names, 'round'
    assert_not_includes dep_names, 'building'
  end

  test 'parse_nix_dependencies returns empty for malformed content' do
    deps = @ecosystem.parse_nix_dependencies('not valid nix')
    assert_equal deps, []
  end

  test 'parse_nix_dependencies handles package names with hyphens' do
    nix_content = <<~NIX
      { lib, stdenv, some-package, another-pkg }:

      stdenv.mkDerivation {
        buildInputs = [ some-package another-pkg ];
      }
    NIX

    deps = @ecosystem.parse_nix_dependencies(nix_content)
    assert deps.any? { |d| d[:package_name] == 'some-package' }
    assert deps.any? { |d| d[:package_name] == 'another-pkg' }
  end

  test 'dependencies_metadata with stubbed fetch' do
    stub_packages({
      'python313Packages.numpy' => {
        'pname' => 'numpy',
        'meta' => { 'position' => 'pkgs/development/python-modules/numpy/default.nix:1' }
      }
    })

    nix_content = <<~NIX
      { lib, buildPythonPackage, blas, lapack, cython }:

      buildPythonPackage {
        pname = "numpy";
        buildInputs = [ blas lapack ];
        nativeBuildInputs = [ cython ];
      }
    NIX

    @ecosystem.define_singleton_method(:fetch_nix_file) { |_pos| nix_content }

    deps = @ecosystem.dependencies_metadata('python313Packages.numpy', '2.3.5', nil)

    assert deps.any? { |d| d[:package_name] == 'blas' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'lapack' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'cython' && d[:kind] == 'build' }
    assert_equal deps.first[:ecosystem], 'nixpkgs'
    assert_equal deps.first[:requirements], '*'
  end

  # Upstream source extraction tests

  test 'infer_upstream_from_attribute_path for python packages' do
    upstream = @ecosystem.infer_upstream_from_attribute_path('python311Packages.requests', 'requests')

    assert_equal upstream[:ecosystem], 'pypi'
    assert_equal upstream[:name], 'requests'
    assert_equal upstream[:purl], 'pkg:pypi/requests'
  end

  test 'infer_upstream_from_attribute_path for ruby gems' do
    upstream = @ecosystem.infer_upstream_from_attribute_path('rubyPackages.rails', 'rails')

    assert_equal upstream[:ecosystem], 'rubygems'
    assert_equal upstream[:name], 'rails'
    assert_equal upstream[:purl], 'pkg:gem/rails'
  end

  test 'infer_upstream_from_attribute_path for npm packages' do
    upstream = @ecosystem.infer_upstream_from_attribute_path('nodePackages.typescript', 'typescript')

    assert_equal upstream[:ecosystem], 'npm'
    assert_equal upstream[:name], 'typescript'
    assert_equal upstream[:purl], 'pkg:npm/typescript'
  end

  test 'infer_upstream_from_attribute_path for haskell packages' do
    upstream = @ecosystem.infer_upstream_from_attribute_path('haskellPackages.aeson', 'aeson')

    assert_equal upstream[:ecosystem], 'hackage'
    assert_equal upstream[:name], 'aeson'
    assert_equal upstream[:purl], 'pkg:hackage/aeson'
  end

  test 'infer_upstream_from_attribute_path for perl packages' do
    upstream = @ecosystem.infer_upstream_from_attribute_path('perlPackages.DBI', 'DBI')

    assert_equal upstream[:ecosystem], 'cpan'
    assert_equal upstream[:name], 'DBI'
    assert_equal upstream[:purl], 'pkg:cpan/DBI'
  end

  test 'infer_upstream_from_attribute_path returns nil for top-level packages' do
    upstream = @ecosystem.infer_upstream_from_attribute_path('ffmpeg', 'ffmpeg')
    assert_nil upstream
  end

  test 'map_package_metadata includes upstream info for python packages' do
    raw_metadata = {
      'pname' => 'requests',
      'version' => '2.32.3',
      'meta' => {}
    }

    mapped = @ecosystem.map_package_metadata(raw_metadata, 'python311Packages.requests')

    assert_equal mapped[:metadata][:upstream_ecosystem], 'pypi'
    assert_equal mapped[:metadata][:upstream_name], 'requests'
    assert_equal mapped[:metadata][:upstream_purl], 'pkg:pypi/requests'
  end

  test 'map_package_metadata omits upstream info for top-level packages' do
    raw_metadata = {
      'pname' => 'ffmpeg',
      'version' => '7.0',
      'meta' => {}
    }

    mapped = @ecosystem.map_package_metadata(raw_metadata, 'ffmpeg')

    refute mapped[:metadata].key?(:upstream_ecosystem)
    refute mapped[:metadata].key?(:upstream_name)
    refute mapped[:metadata].key?(:upstream_purl)
  end

  test 'extract_upstream_source for python package with fetchPypi' do
    nix_content = File.read(Rails.root.join('test/fixtures/files/nixpkgs/requests.nix'))

    upstream = @ecosystem.extract_upstream_source(nix_content)

    assert_equal upstream[:ecosystem], 'pypi'
    assert_equal upstream[:name], 'requests'
    assert_equal upstream[:purl], 'pkg:pypi/requests'
  end

  test 'extract_upstream_source for rust package' do
    nix_content = File.read(Rails.root.join('test/fixtures/files/nixpkgs/ripgrep.nix'))

    upstream = @ecosystem.extract_upstream_source(nix_content)

    assert_equal upstream[:ecosystem], 'cargo'
    assert_equal upstream[:name], 'ripgrep'
    assert_equal upstream[:purl], 'pkg:cargo/ripgrep'
  end

  test 'extract_upstream_source for npm package' do
    nix_content = File.read(Rails.root.join('test/fixtures/files/nixpkgs/typescript.nix'))

    upstream = @ecosystem.extract_upstream_source(nix_content)

    assert_equal upstream[:ecosystem], 'npm'
    assert_equal upstream[:name], 'typescript'
    assert_equal upstream[:purl], 'pkg:npm/typescript'
  end

  test 'extract_upstream_source for go module' do
    nix_content = File.read(Rails.root.join('test/fixtures/files/nixpkgs/go-ethereum.nix'))

    upstream = @ecosystem.extract_upstream_source(nix_content)

    assert_equal upstream[:ecosystem], 'go'
    assert_equal upstream[:name], 'go-ethereum'
    assert_equal upstream[:purl], 'pkg:golang/go-ethereum'
  end

  test 'extract_upstream_source for ruby gem' do
    nix_content = File.read(Rails.root.join('test/fixtures/files/nixpkgs/bundler.nix'))

    upstream = @ecosystem.extract_upstream_source(nix_content)

    assert_equal upstream[:ecosystem], 'rubygems'
    assert_equal upstream[:name], 'bundler'
    assert_equal upstream[:purl], 'pkg:gem/bundler'
  end

  test 'extract_upstream_source returns nil for packages without recognized builder' do
    nix_content = <<~NIX
      { lib, stdenv }:
      stdenv.mkDerivation {
        pname = "custom";
        version = "1.0";
      }
    NIX

    upstream = @ecosystem.extract_upstream_source(nix_content)
    assert_nil upstream
  end

  test 'extract_pname extracts pname from nix content' do
    content = 'pname = "my-package";'
    assert_equal @ecosystem.extract_pname(content), 'my-package'
  end

  test 'extract_python_package_name from fetchPypi with explicit pname' do
    content = <<~NIX
      src = fetchPypi {
        pname = "PyYAML";
        version = "6.0";
      };
    NIX

    assert_equal @ecosystem.extract_python_package_name(content), 'PyYAML'
  end

  test 'extract_python_package_name from fetchPypi with inherit' do
    content = <<~NIX
      pname = "requests";
      src = fetchPypi {
        inherit pname version;
      };
    NIX

    assert_equal @ecosystem.extract_python_package_name(content), 'requests'
  end

  test 'extract_ruby_gem_name uses gemName over pname' do
    content = <<~NIX
      pname = "bundler";
      gemName = "bundler";
    NIX

    assert_equal @ecosystem.extract_ruby_gem_name(content), 'bundler'
  end

  test 'build_upstream_purl generates correct purls' do
    assert_equal @ecosystem.build_upstream_purl('pypi', 'requests'), 'pkg:pypi/requests'
    assert_equal @ecosystem.build_upstream_purl('cargo', 'serde'), 'pkg:cargo/serde'
    assert_equal @ecosystem.build_upstream_purl('npm', 'lodash'), 'pkg:npm/lodash'
    assert_equal @ecosystem.build_upstream_purl('go', 'cobra'), 'pkg:golang/cobra'
    assert_equal @ecosystem.build_upstream_purl('rubygems', 'rails'), 'pkg:gem/rails'
    assert_equal @ecosystem.build_upstream_purl('hackage', 'aeson'), 'pkg:hackage/aeson'
  end

  test 'build_upstream_purl returns nil for unknown ecosystems' do
    assert_nil @ecosystem.build_upstream_purl('unknown', 'package')
    assert_nil @ecosystem.build_upstream_purl(nil, 'package')
    assert_nil @ecosystem.build_upstream_purl('pypi', nil)
  end

  test 'download_and_cache_packages raises error when download fails' do
    stub_request(:get, "https://channels.nixos.org/nixos-unstable/packages.json.br")
      .to_return(status: 500, body: "")

    error = assert_raises(RuntimeError) do
      @ecosystem.download_and_cache_packages(ttl: 0.seconds)
    end
    assert_match(/Failed to download/, error.message)
  end

  test 'download_and_cache_packages succeeds with valid brotli response' do
    json_content = '{"packages":{"test":{"pname":"test","version":"1.0"}}}'
    compressed = Brotli.deflate(json_content)

    stub_request(:get, "https://channels.nixos.org/nixos-unstable/packages.json.br")
      .to_return(status: 200, body: compressed)

    cache_file = @ecosystem.download_and_cache_packages(ttl: 0.seconds)

    assert File.exist?(cache_file)
    assert_equal json_content, File.read(cache_file)

    FileUtils.rm_f(cache_file)
  end
end
