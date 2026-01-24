require "test_helper"

class NixpkgsTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'nixpkgs-unstable', url: 'https://channels.nixos.org/nixos-unstable', ecosystem: 'nixpkgs', version: 'unstable')
    @ecosystem = Ecosystem::Nixpkgs.new(@registry)
    @package = Package.new(ecosystem: 'nixpkgs', name: 'numpy', metadata: { 'position' => 'pkgs/development/python-modules/numpy/2.nix:205' })
    @version = @package.versions.build(number: '2.3.5')
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

    mapped = @ecosystem.map_package_metadata(raw_metadata)

    assert_equal mapped[:name], 'numpy'
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

    mapped = @ecosystem.map_package_metadata(raw_metadata)
    assert_equal mapped[:licenses], 'MIT, Apache-2.0'
  end

  test 'map_package_metadata returns false for blank metadata' do
    assert_equal @ecosystem.map_package_metadata(nil), false
    assert_equal @ecosystem.map_package_metadata({}), false
    assert_equal @ecosystem.map_package_metadata({ 'pname' => nil }), false
  end

  test 'versions_metadata' do
    @ecosystem.instance_variable_set(:@packages, {
      'numpy' => {
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

    versions = @ecosystem.versions_metadata({ name: 'numpy' })

    assert_equal versions.length, 1
    assert_equal versions[0][:number], '2.3.5'
    assert_equal versions[0][:licenses], 'BSD-3-Clause'
    assert_equal versions[0][:metadata][:nix_attribute], 'python3.13-numpy-2.3.5'
  end

  test 'maintainers_metadata' do
    @ecosystem.instance_variable_set(:@packages, {
      'numpy' => {
        'pname' => 'numpy',
        'meta' => {
          'maintainers' => [
            { 'name' => 'Doron Behar', 'github' => 'doronbehar', 'email' => 'me@doronbehar.com' }
          ]
        }
      }
    })

    maintainers = @ecosystem.maintainers_metadata('numpy')

    assert_equal maintainers.length, 1
    assert_equal maintainers[0][:uuid], 'doronbehar'
    assert_equal maintainers[0][:name], 'Doron Behar'
    assert_equal maintainers[0][:email], 'me@doronbehar.com'
    assert_equal maintainers[0][:url], 'https://github.com/doronbehar'
  end

  test 'maintainers_metadata returns empty for missing maintainers' do
    @ecosystem.instance_variable_set(:@packages, {
      'test' => { 'pname' => 'test', 'meta' => {} }
    })

    maintainers = @ecosystem.maintainers_metadata('test')
    assert_equal maintainers, []
  end
end
