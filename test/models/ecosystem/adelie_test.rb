require "test_helper"

class AdelieTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'Adelie', url: 'https://pkg.adelielinux.org', ecosystem: 'adelie')
    @ecosystem = Ecosystem::Adelie.new(@registry)
    @package = Package.new(ecosystem: 'adelie', name: 'abuild', metadata: { 'repository' => 'system', 'architecture' => 'x86_64' })

    # Load fixture packages
    @fixture_packages = load_fixture_packages

    # Mock packages method to use fixture data instead of downloading
    @ecosystem.stubs(:packages).returns(@fixture_packages)
  end

  def load_fixture_packages
    all_packages = []
    ['system', 'user'].each do |repository|
      fixture_file = Rails.root.join('test/fixtures/files/adelie', "APKINDEX-#{repository}.tar.gz")
      packages = []
      package = {'r' => repository}

      Dir.mktmpdir do |dir|
        destination = "#{dir}/APKINDEX"
        `tar -xzf #{fixture_file} -C #{dir}`

        File.foreach(destination) do |line|
          if line.blank?
            packages << package
            package = {'r' => repository}
          end
          key = line.split(':')[0]
          value = line.split(':')[1..-1].join(':').strip
          package[key] = value if key.present?
        end
        packages << package if package['P'].present?
      end
      all_packages += packages
    end
    all_packages
  end

  test 'maintainers_metadata returns empty array when package not found' do
    maintainers = @ecosystem.maintainers_metadata('nonexistent-package')
    assert_equal [], maintainers
  end

  test 'maintainers_metadata returns maintainer data when package exists' do
    maintainers = @ecosystem.maintainers_metadata('abuild')
    assert_equal 1, maintainers.length
    assert_equal 'awilfox@adelielinux.org', maintainers.first[:uuid]
    assert_equal 'A. Wilcox', maintainers.first[:name]
  end

  test 'dependencies_metadata returns empty array when package not found' do
    dependencies = @ecosystem.dependencies_metadata('nonexistent-package', nil, {})
    assert_equal [], dependencies
  end

  test 'dependencies_metadata returns dependencies when package exists' do
    dependencies = @ecosystem.dependencies_metadata('abuild', nil, {})
    assert dependencies.length > 0
    assert dependencies.all? { |d| d[:ecosystem] == 'adelie' }
    assert dependencies.all? { |d| d[:kind] == 'install' }
  end

  test 'versions_metadata returns empty array when package not found' do
    versions = @ecosystem.versions_metadata({ name: 'nonexistent-package' })
    assert_equal [], versions
  end

  test 'versions_metadata returns version data when package exists' do
    versions = @ecosystem.versions_metadata({ name: 'abuild' })
    assert_equal 1, versions.length
    assert versions.first[:number].present?
    assert versions.first[:published_at].is_a?(Time)
    assert_equal 'x86_64', versions.first[:metadata][:architecture]
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_equal registry_url, 'https://pkg.adelielinux.org/current/abuild'
  end

  test 'download_url with version' do
    version = @package.versions.build(number: '3.5-r0')
    download_url = @ecosystem.download_url(@package, version)
    assert_equal download_url, 'https://distfiles.adelielinux.org/adelie/current/system/x86_64/abuild-3.5-r0.apk'
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, 'apk add abuild'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:apk/adelie/abuild?arch=x86_64'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    version = @package.versions.build(number: '3.5-r0')
    purl = @ecosystem.purl(@package, version)
    assert_equal purl, 'pkg:apk/adelie/abuild@3.5-r0?arch=x86_64'
    assert Purl.parse(purl)
  end

  test 'recently_updated_package_names handles packages with nil timestamps' do
    packages_with_nil_timestamp = [
      { 'P' => 'pkg-with-time', 't' => '1700000000', 'r' => 'system' },
      { 'P' => 'pkg-without-time', 't' => nil, 'r' => 'system' },
      { 'P' => 'pkg-missing-time', 'r' => 'system' }
    ]
    @ecosystem.stubs(:packages).returns(packages_with_nil_timestamp)

    result = @ecosystem.recently_updated_package_names
    assert_includes result, 'pkg-with-time'
    assert_includes result, 'pkg-without-time'
    assert_includes result, 'pkg-missing-time'
    assert_equal 'pkg-with-time', result.first
  end
end
