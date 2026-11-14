require "test_helper"

class VcpkgTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'vcpkg.org', url: 'https://vcpkg.org', ecosystem: 'vcpkg')
    @ecosystem = Ecosystem::Vcpkg.new(@registry)
    @package = Package.new(ecosystem: 'vcpkg', name: 'zziplib')
    @version = @package.versions.build(number: '1.26.8')
  end

  test 'registry_url' do
    registry_url = @ecosystem.registry_url(@package)
    assert_nil registry_url
  end

  test 'registry_url with version' do
    registry_url = @ecosystem.registry_url(@package, @version)
    assert_nil registry_url
  end

  test 'download_url' do
    download_url = @ecosystem.download_url(@package, @version)
    assert_nil download_url
  end

  test 'documentation_url' do
    documentation_url = @ecosystem.documentation_url(@package)
    assert_nil documentation_url
  end

  test 'documentation_url with version' do
    documentation_url = @ecosystem.documentation_url(@package, @version.number)
    assert_nil documentation_url
  end

  test 'install_command' do
    install_command = @ecosystem.install_command(@package)
    assert_equal install_command, '.\vcpkg install zziplib'
  end

  test 'install_command with version' do
    install_command = @ecosystem.install_command(@package, @version.number)
    assert_equal install_command, '.\vcpkg install zziplib'
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal purl, 'pkg:vcpkg/zziplib'
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal purl, 'pkg:vcpkg/zziplib@1.26.8'
    assert Purl.parse(purl)
  end

  test 'all_package_names' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/versions/baseline.json')
      .to_return(status: 200, body: file_fixture('vcpkg/baseline.json'))
    all_package_names = @ecosystem.all_package_names
    assert_equal ['7zip', 'gz-common', 'gz-math', 'zlib', 'zziplib'], all_package_names
  end

  test 'recently_updated_package_names' do
    stub_request(:get, "https://github.com/microsoft/vcpkg/commits/master.atom")
      .to_return(status: 200, body: <<~XML)
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry><title>[zlib, zziplib, gz-*] Update ports</title></entry>
          <entry><title>[7zip] Update port</title></entry>
          <entry><title>[ZLIB] Update port again</title></entry>
          <entry><title>[ci] Update workflow</title></entry>
          <entry><title>Maintenance [zziplib]</title></entry>
        </feed>
      XML
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/versions/baseline.json')
      .to_return(status: 200, body: file_fixture('vcpkg/baseline.json'))
    recently_updated_package_names = @ecosystem.recently_updated_package_names
    assert_equal ['zlib', 'zziplib', 'gz-common', 'gz-math', '7zip'], recently_updated_package_names
  end

  test 'package_metadata' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json')
      .to_return(status: 200, body: file_fixture('vcpkg/zziplib.json'))
    package_metadata = @ecosystem.package_metadata('zziplib')

    assert_equal package_metadata[:name], "zziplib"
    assert_equal package_metadata[:description], "library providing read access on ZIP-archives"
    assert_equal package_metadata[:homepage], "https://github.com/gdraheim/zziplib"
    assert_equal package_metadata[:licenses], "LGPL-2.0-or-later OR MPL-1.1"
    assert_equal package_metadata[:repository_url], "https://github.com/gdraheim/zziplib"
    assert_nil package_metadata[:keywords_array]
  end

  test 'versions_metadata' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json')
      .to_return(status: 200, body: file_fixture('vcpkg/zziplib.json'))
    package_metadata = @ecosystem.package_metadata('zziplib')
    versions_metadata = @ecosystem.versions_metadata(package_metadata)

    assert_equal versions_metadata, [{:number=>"0.13.80"}]
  end

  test 'dependencies_metadata' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/7zip/vcpkg.json')
      .to_return(status: 200, body: file_fixture('vcpkg/7zip.json'))
    package_metadata = @ecosystem.package_metadata('7zip')
    dependencies_metadata = @ecosystem.dependencies_metadata('7zip', '26.6', package_metadata)

    assert_equal dependencies_metadata, [
      {:package_name=>"vcpkg-cmake", :requirements=>"*", :kind=>"runtime", :ecosystem=>"vcpkg"},
      {:package_name=>"vcpkg-cmake-config", :requirements=>"*", :kind=>"runtime", :ecosystem=>"vcpkg"}
    ]
  end

  test 'scheduled recent updates enqueue individual ports and workers persist current manifests' do
    @registry.save!
    stub_request(:get, 'https://github.com/microsoft/vcpkg/commits/master.atom')
      .to_return(status: 200, body: '<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>[7zip,zziplib,gz-*] Update ports</title></entry><entry><title>[7zip] Update again</title></entry></feed>')
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/versions/baseline.json')
      .to_return(status: 200, body: file_fixture('vcpkg/baseline.json'))
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/7zip/vcpkg.json')
      .to_return(status: 200, body: file_fixture('vcpkg/7zip.json'))
    SyncPackageWorker.clear

    @registry.sync_recently_updated_packages_async

    jobs = SyncPackageWorker.jobs.map { |job| job['args'] }
    assert_equal ['7zip', 'zziplib', 'gz-common', 'gz-math'].map { |name| [@registry.id, name, true] }, jobs
    SyncPackageWorker.new.perform(*jobs.first)

    package = @registry.packages.find_by!(name: '7zip')
    assert_equal ['26.6'], package.versions.pluck(:number)
    assert_equal ['vcpkg-cmake', 'vcpkg-cmake-config'], package.versions.first.dependencies.pluck(:package_name).sort
    assert_not_nil package.last_synced_at
    assert_not_requested(:get, 'https://vcpkg.io/output.json')
  ensure
    SyncPackageWorker.clear
  end

  test 'manifest version fields and array descriptions' do
    %w[version version-semver version-date version-string].each do |field|
      manifest = JSON.parse(file_fixture('vcpkg/zziplib.json').read)
      manifest[field] = manifest.delete('version')
      manifest['description'] = ['ZIP', 'utilities']
      stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json')
        .to_return(status: 200, body: manifest.to_json)
      ecosystem = Ecosystem::Vcpkg.new(@registry)

      metadata = ecosystem.package_metadata('zziplib')

      assert_equal 'ZIP utilities', metadata[:description]
      assert_equal [{number: '0.13.80'}], ecosystem.versions_metadata(metadata)
    end
  end

  test 'check_status reuses a fetched manifest' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json')
      .to_return(status: 200, body: file_fixture('vcpkg/zziplib.json'))

    @ecosystem.package_metadata('zziplib')

    assert_nil @ecosystem.check_status(@package)
    assert_requested(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json', times: 1)
  end

  test 'missing manifests report removed packages' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json')
      .to_return(status: 404)

    assert_equal 'removed', @ecosystem.check_status(@package)
  end

  test 'worker requests for domain-like package names do not send the service API key to GitHub' do
    previous_key = ENV['ECOSYSTEMS_API_KEY']
    ENV['ECOSYSTEMS_API_KEY'] = 'test-service-key'
    @registry.save!
    manifest = stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/probe.ecosyste.ms/vcpkg.json')
      .with { |request| request.headers['X-Api-Key'].nil? }
      .to_return(status: 404)

    SyncPackageWorker.new.perform(@registry.id, 'probe.ecosyste.ms', true)

    assert_requested manifest, times: 1
    assert_empty @registry.packages
  ensure
    ENV['ECOSYSTEMS_API_KEY'] = previous_key
  end

  test 'worker imports manifests with separator-heavy homepage lists' do
    previous_timeout = Regexp.timeout
    Regexp.timeout = 0.1
    @registry.save!
    manifest = JSON.parse(file_fixture('vcpkg/7zip.json').read)
    manifest['homepage'] = "https://example.com/#{"\t" * 20_000}x; https://github.com/owner/project"
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/7zip/vcpkg.json')
      .to_return(status: 200, body: manifest.to_json)

    SyncPackageWorker.new.perform(@registry.id, '7zip', true)

    package = @registry.packages.find_by!(name: '7zip')
    assert_equal 'https://github.com/owner/project', package.repository_url
    assert_equal ['26.6'], package.versions.pluck(:number)
  ensure
    Regexp.timeout = previous_timeout
  end

  test 'manifest failures do not report removed packages' do
    stub_request(:get, 'https://raw.githubusercontent.com/microsoft/vcpkg/master/ports/zziplib/vcpkg.json')
      .to_return(status: 503, body: 'Service unavailable')

    assert_raises(RuntimeError) { @ecosystem.check_status(@package) }
  end
end
