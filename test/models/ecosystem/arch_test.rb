require "test_helper"

class ArchTest < ActiveSupport::TestCase
  setup do
    @official_registry = Registry.new(default: true, name: 'archlinux.org', url: 'https://archlinux.org', ecosystem: 'arch', metadata: { 'kind' => 'official' })
    @official = Ecosystem::Arch.new(@official_registry)
    @official_package = Package.new(ecosystem: 'arch', name: 'jq', metadata: { 'repo' => 'extra', 'arch' => 'x86_64', 'pkgbase' => 'jq' })
    @official_version = @official_package.versions.build(number: '1.8.1-3', metadata: { 'filename' => 'jq-1.8.1-3-x86_64.pkg.tar.zst' })

    @aur_registry = Registry.new(default: false, name: 'aur.archlinux.org', url: 'https://aur.archlinux.org', ecosystem: 'arch', metadata: { 'kind' => 'aur' })
    @aur = Ecosystem::Arch.new(@aur_registry)
    @aur_package = Package.new(ecosystem: 'arch', name: 'yay', metadata: { 'pkgbase' => 'yay', 'urlpath' => '/cgit/aur.git/snapshot/yay.tar.gz' })
    @aur_version = @aur_package.versions.build(number: '12.5.7-1')
  end

  test 'aur? branches on registry kind' do
    refute @official.aur?
    assert @aur.aur?
  end

  test 'registry_url official' do
    assert_equal 'https://archlinux.org/packages/extra/x86_64/jq/', @official.registry_url(@official_package)
  end

  test 'registry_url aur' do
    assert_equal 'https://aur.archlinux.org/packages/yay', @aur.registry_url(@aur_package)
  end

  test 'install_command' do
    assert_equal 'pacman -S jq', @official.install_command(@official_package)
    assert_equal 'yay -S yay', @aur.install_command(@aur_package)
  end

  test 'download_url official' do
    assert_equal 'https://geo.mirror.pkgbuild.com/extra/os/x86_64/jq-1.8.1-3-x86_64.pkg.tar.zst', @official.download_url(@official_package, @official_version)
  end

  test 'download_url aur' do
    assert_equal 'https://aur.archlinux.org/cgit/aur.git/snapshot/yay.tar.gz', @aur.download_url(@aur_package, @aur_version)
  end

  test 'download_url returns nil without version' do
    assert_nil @official.download_url(@official_package, nil)
    assert_nil @aur.download_url(@aur_package, nil)
  end

  test 'purl official' do
    purl = @official.purl(@official_package, @official_version)
    assert_equal 'pkg:alpm/arch/jq@1.8.1-3?arch=x86_64&upstream=jq', purl
    assert Purl.parse(purl)
  end

  test 'purl aur with no arch qualifier' do
    purl = @aur.purl(@aur_package, @aur_version)
    assert_equal 'pkg:alpm/arch/yay@12.5.7-1?repository_url=https://aur.archlinux.org&upstream=yay', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names official paginates' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?page=1")
      .to_return({ status: 200, body: file_fixture('arch/official_page1.json') })
    stub_request(:get, "https://archlinux.org/packages/search/json/?page=2")
      .to_return({ status: 200, body: file_fixture('arch/official_page2.json') })
    names = @official.all_package_names
    assert_equal %w[jq iptables zlib], names
  end

  test 'all_package_names aur from gzipped list' do
    body = Zlib.gzip(file_fixture('arch/aur_packages').read)
    stub_request(:get, "https://aur.archlinux.org/packages.gz")
      .to_return({ status: 200, body: body, headers: { 'Content-Type' => 'application/gzip' } })
    names = @aur.all_package_names
    assert_equal %w[yay yay-bin paru visual-studio-code-bin], names
  end

  test 'all_package_names aur handles plain text body' do
    stub_request(:get, "https://aur.archlinux.org/packages.gz")
      .to_return({ status: 200, body: file_fixture('arch/aur_packages') })
    names = @aur.all_package_names
    assert_equal 4, names.length
    refute names.any? { |n| n.start_with?('#') }
  end

  test 'recently_updated_package_names official' do
    stub_request(:get, "https://archlinux.org/feeds/packages/")
      .to_return({ status: 200, body: file_fixture('arch/official_feed.xml') })
    assert_equal %w[river-classic jq], @official.recently_updated_package_names
  end

  test 'recently_updated_package_names aur' do
    stub_request(:get, "https://aur.archlinux.org/rss/modified")
      .to_return({ status: 200, body: file_fixture('arch/aur_rss.xml') })
    stub_request(:get, "https://aur.archlinux.org/rss/")
      .to_return({ status: 200, body: file_fixture('arch/aur_rss.xml') })
    assert_equal %w[arch-update brave-nightly-bin], @aur.recently_updated_package_names
  end

  test 'package_metadata official' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=jq")
      .to_return({ status: 200, body: file_fixture('arch/official_jq.json') })
    pkg = @official.package_metadata('jq')

    assert_equal 'jq', pkg[:name]
    assert_equal 'Command-line JSON processor', pkg[:description]
    assert_equal 'https://jqlang.github.io/jq/', pkg[:homepage]
    assert_equal 'MIT', pkg[:licenses]
    assert_equal 'extra', pkg[:namespace]
    assert_equal 'extra', pkg[:metadata][:repo]
    assert_equal 'jq', pkg[:metadata][:pkgbase]
    assert_equal 'https://gitlab.archlinux.org/archlinux/packaging/packages/jq', pkg[:metadata][:packaging_repository_url]
  end

  test 'package_metadata official with epoch' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=iptables")
      .to_return({ status: 200, body: file_fixture('arch/official_iptables.json') })
    pkg = @official.package_metadata('iptables')
    assert_equal '1:1.8.13-1', pkg[:version_data][:number]
  end

  test 'package_metadata aur' do
    stub_request(:get, "https://aur.archlinux.org/rpc/v5/info?arg[]=yay")
      .to_return({ status: 200, body: file_fixture('arch/aur_yay.json') })
    pkg = @aur.package_metadata('yay')

    assert_equal 'yay', pkg[:name]
    assert_equal 'Yet another yogurt. Pacman wrapper and AUR helper written in go.', pkg[:description]
    assert_equal 'https://github.com/Jguer/yay', pkg[:homepage]
    assert_equal 'GPL-3.0-or-later', pkg[:licenses]
    assert_equal 'https://github.com/Jguer/yay', pkg[:repository_url]
    assert_equal 'jguer', pkg[:namespace]
    assert_equal 'yay', pkg[:metadata][:pkgbase]
    assert_equal 2574, pkg[:metadata][:num_votes]
    assert_includes pkg[:keywords_array], 'AUR'
  end

  test 'package_metadata returns false when not found' do
    stub_request(:get, "https://aur.archlinux.org/rpc/v5/info?arg[]=nope")
      .to_return({ status: 200, body: '{"resultcount":0,"results":[],"type":"multiinfo","version":5}' })
    assert_equal false, @aur.package_metadata('nope')
  end

  test 'versions_metadata official' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=jq")
      .to_return({ status: 200, body: file_fixture('arch/official_jq.json') })
    pkg = @official.package_metadata('jq')
    versions = @official.versions_metadata(pkg)

    assert_equal 1, versions.length
    assert_equal '1.8.1-3', versions.first[:number]
    assert_equal '2026-04-21T13:46:57Z', versions.first[:published_at]
    assert_equal 'jq-1.8.1-3-x86_64.pkg.tar.zst', versions.first[:metadata][:filename]
  end

  test 'versions_metadata aur' do
    stub_request(:get, "https://aur.archlinux.org/rpc/v5/info?arg[]=yay")
      .to_return({ status: 200, body: file_fixture('arch/aur_yay.json') })
    pkg = @aur.package_metadata('yay')
    versions = @aur.versions_metadata(pkg)

    assert_equal 1, versions.length
    assert_equal '12.5.7-1', versions.first[:number]
    assert_equal Time.at(1765742501), versions.first[:published_at]
  end

  test 'dependencies_metadata official' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=jq")
      .to_return({ status: 200, body: file_fixture('arch/official_jq.json') })
    pkg = @official.package_metadata('jq')
    deps = @official.dependencies_metadata('jq', '1.8.1-3', pkg)

    runtime = deps.select { |d| d[:kind] == 'runtime' }
    assert_equal %w[glibc oniguruma], runtime.map { |d| d[:package_name] }
    assert_equal '*', runtime.first[:requirements]
    assert_equal 'arch', runtime.first[:ecosystem]
    refute runtime.first[:optional]

    build = deps.select { |d| d[:kind] == 'build' }
    assert_includes build.map { |d| d[:package_name] }, 'git'
  end

  test 'dependencies_metadata aur with version constraints' do
    stub_request(:get, "https://aur.archlinux.org/rpc/v5/info?arg[]=yay")
      .to_return({ status: 200, body: file_fixture('arch/aur_yay.json') })
    pkg = @aur.package_metadata('yay')
    deps = @aur.dependencies_metadata('yay', '12.5.7-1', pkg)

    pacman = deps.find { |d| d[:package_name] == 'pacman' }
    assert_equal '>6.1', pacman[:requirements]
    assert_equal 'runtime', pacman[:kind]

    go = deps.find { |d| d[:package_name] == 'go' }
    assert_equal '>=1.24', go[:requirements]
    assert_equal 'build', go[:kind]

    sudo = deps.find { |d| d[:package_name] == 'sudo' }
    assert_equal 'optional', sudo[:kind]
    assert sudo[:optional]
  end

  test 'dependencies_metadata empty for non-current version' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=jq")
      .to_return({ status: 200, body: file_fixture('arch/official_jq.json') })
    pkg = @official.package_metadata('jq')
    assert_equal [], @official.dependencies_metadata('jq', '0.0.1-1', pkg)
  end

  test 'parse_dependency strips optdepend description' do
    dep = @official.parse_dependency('apparmor: additional security features', 'optional')
    assert_equal 'apparmor', dep[:package_name]
    assert_equal '*', dep[:requirements]
    assert dep[:optional]
  end

  test 'maintainers_metadata official' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=jq")
      .to_return({ status: 200, body: file_fixture('arch/official_jq.json') })
    maintainers = @official.maintainers_metadata('jq')
    assert_equal 4, maintainers.length
    assert_equal 'felixonmars', maintainers.first[:login]
    assert_equal 'https://archlinux.org/packages/?maintainer=felixonmars', maintainers.first[:url]
  end

  test 'maintainers_metadata aur' do
    stub_request(:get, "https://aur.archlinux.org/rpc/v5/info?arg[]=yay")
      .to_return({ status: 200, body: file_fixture('arch/aur_yay.json') })
    maintainers = @aur.maintainers_metadata('yay')
    assert_equal 1, maintainers.length
    assert_equal 'jguer', maintainers.first[:login]
    assert_equal 'https://aur.archlinux.org/account/jguer', maintainers.first[:url]
  end

  test 'check_status removed when missing' do
    stub_request(:get, "https://archlinux.org/packages/search/json/?name=gone")
      .to_return({ status: 200, body: '{"results":[]}' })
    assert_equal 'removed', @official.check_status(Package.new(name: 'gone'))
  end

  test 'has_dependent_repos' do
    refute @official.has_dependent_repos?
  end
end
