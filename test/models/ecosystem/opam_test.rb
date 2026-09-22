require 'test_helper'

class OpamTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.create!(default: true, name: 'opam.ocaml.org', url: 'https://opam.ocaml.org', ecosystem: 'opam')
    @ecosystem = @registry.ecosystem_instance
    @response = JSON.parse(file_fixture('opam/lwt.json').read)
    stub_archive_index({})
    %w[5.9.2 5.10.1 6.1.2].each do |version|
      stub_request(:get, "https://opam.ocaml.org/packages/lwt/lwt.#{version}/opam")
        .to_return(status: 200, body: file_fixture("opam/lwt.#{version}.opam").read)
    end
    stub_request(:post, 'https://ocaml.org/graphql')
      .with { |req| !JSON.parse(req.body)['query'].include?('packgeByVersions') }
      .to_return(status: 200, body: { data: { package: { name: 'lwt' } } }.to_json)
  end

  test 'sync package persists registry metadata, releases and conditional dependencies' do
    request = stub_request(:post, 'https://ocaml.org/graphql').with do |req|
      body = JSON.parse(req.body)
      body['variables'] == { 'name' => 'lwt' } && body['query'].include?('packgeByVersions')
    end.to_return(status: 200, body: @response.to_json)

    package = @registry.sync_package('lwt').reload

    assert_equal 'Promises and event-driven I/O', package.description
    assert_equal 'https://github.com/ocsigen/lwt', package.repository_url
    assert_equal 'MIT', package.licenses
    assert_equal ['Jérôme Vouillon', 'Jérémie Dimino'], package.metadata['authors']
    assert_equal 3, package.versions_count
    assert_equal '6.1.2', package.latest_release_number
    assert_equal 'pkg:opam/lwt', package.purl

    version = package.versions.find_by!(number: '5.9.2')
    assert_equal Time.at(1756310969).utc, version.read_attribute(:published_at)
    assert_equal 'https://github.com/ocsigen/lwt/archive/refs/tags/5.9.2.tar.gz', version.download_url
    assert_equal 2, version.metadata['checksums'].length
    assert_equal 'pkg:opam/lwt@5.9.2', version.purl
    assert_equal 'opam install lwt.5.9.2', version.install_command
    assert_equal 'https://opam.ocaml.org/packages/lwt/lwt.5.9.2/', version.registry_url
    assert_equal 'https://ocaml.org/p/lwt/5.9.2/doc/index.html', version.documentation_url

    dependency = version.dependencies.find_by!(package_name: 'cppo')
    assert_equal 'build', dependency.kind
    assert_equal 'build & >= "1.1"', dependency.requirements
    refute dependency.optional
    assert_equal 'opam', dependency.ecosystem
    assert_equal 'documentation', version.dependencies.find_by!(package_name: 'odoc').kind
    assert_equal 'development', version.dependencies.find_by!(package_name: 'ocamlfind').kind
    assert_equal '>= "4.08" & < "5.5"', version.dependencies.find_by!(package_name: 'ocaml').requirements
    optional = version.dependencies.find_by!(package_name: 'conf-libev')
    assert optional.optional
    assert_equal '*', optional.requirements
    assert_requested request, times: 1
  end

  test 'discovery paginates through the registry entrypoint' do
    packages = 500.times.map { |index| { name: "package-#{index}" } }
    first_page = stub_request(:post, 'https://ocaml.org/graphql')
      .with { |req| JSON.parse(req.body)['variables'] == { 'limit' => 500, 'offset' => 0 } }
      .to_return(status: 200, body: { data: { allPackages: { totalPackages: 501, packages: packages } } }.to_json)
    last_page = stub_request(:post, 'https://ocaml.org/graphql')
      .with { |req| JSON.parse(req.body)['variables'] == { 'limit' => 500, 'offset' => 500 } }
      .to_return(status: 200, body: { data: { allPackages: { totalPackages: 501, packages: [{ name: 'lwt' }] } } }.to_json)

    assert_equal packages.map { |package| package[:name] } + ['lwt'], @registry.all_package_names
    assert_requested first_page
    assert_requested last_page
  end

  test 'recent discovery sorts publication timestamps rather than package names' do
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: {
      data: { allPackages: { totalPackages: 3, packages: [
        { name: 'base', publication: 10 }, { name: 'dune', publication: 30 }, { name: 'lwt', publication: 20 }
      ] } }
    }.to_json)

    assert_equal %w[dune lwt base], @registry.recently_updated_package_names
  end

  test 'GraphQL errors with a successful HTTP status do not create a partial package' do
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: {
      errors: [{ message: 'Cannot load versions' }], data: @response['data']
    }.to_json)

    assert_no_difference ['Package.count', 'Version.count', 'Dependency.count'] do
      error = assert_raises(RuntimeError) { @registry.sync_package('lwt') }
      assert_includes error.message, 'Cannot load versions'
    end
  end

  test 'HTTP errors do not create packages' do
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 503, body: 'Unavailable')

    assert_no_difference 'Package.count' do
      assert_raises(Faraday::ServerError) { @registry.sync_package('lwt') }
    end
  end

  test 'a missing package does not mark historical records removed' do
    package = @registry.packages.create!(name: 'archived', ecosystem: 'opam')
    version = package.versions.create!(number: '1.0')
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: {
      errors: [{ message: 'No package matching archived was found', path: ['package'] }], data: nil
    }.to_json)

    assert_equal false, @ecosystem.check_status(package)
    package.check_status
    assert_nil package.reload.status
    assert_nil version.reload.status
  end

  test 'sync preserves historical versions absent from the API' do
    package = @registry.packages.create!(name: 'lwt', ecosystem: 'opam')
    historical = package.versions.create!(number: '1.0.0')
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: @response.to_json)

    @registry.sync_package('lwt', force: true)

    assert_nil historical.reload.status
    assert_equal 4, package.reload.versions_count
  end

  test 'sync supports packages without source archives or publication dates' do
    @response['data']['packgeByVersions']['packages'].each do |version|
      version['url'] = nil
      version['publication'] = 0
    end
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: @response.to_json)

    package = @registry.sync_package('lwt')

    assert_nil package.versions.first.download_url
    assert_nil package.versions.first.read_attribute(:published_at)
  end

  test 'compound dependency filters remain intact' do
    version = @response['data']['packgeByVersions']['packages'].first
    stub_request(:get, "https://opam.ocaml.org/packages/lwt/lwt.#{version['version']}/opam")
      .to_return(status: 200, body: <<~OPAM)
        opam-version: "2.0"
        depends: [
          "alcotest" {with-test & >= "1.0"}
          "dune" {build | with-test}
          "unix" {os != "win32"}
        ]
      OPAM
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: @response.to_json)

    package = @registry.sync_package('lwt')
    dependencies = package.versions.find_by!(number: version['version']).dependencies

    assert_equal 'test', dependencies.find_by!(package_name: 'alcotest').kind
    assert_equal 'build | with-test', dependencies.find_by!(package_name: 'dune').requirements
    assert_equal 'os != "win32"', dependencies.find_by!(package_name: 'unix').requirements
  end

  test 'sync chooses opam versions by version order rather than publication date' do
    versions = %w[1.0~beta2 1.0 1.0+2 1.0+10 2.0~beta1]
    @response['data']['packgeByVersions']['packages'] = versions.each_with_index.map do |number, index|
      @response['data']['package'].merge('version' => number, 'publication' => 1756310969 - index)
    end
    versions.each do |version|
      stub_request(:get, "https://opam.ocaml.org/packages/lwt/lwt.#{version}/opam")
        .to_return(status: 200, body: 'opam-version: "2.0"')
    end
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: @response.to_json)

    package = @registry.sync_package('lwt').reload

    assert_equal '1.0+10', package.latest_release_number
    assert_equal versions.reverse, package.versions.sort.map(&:number)
    assert package.versions.find_by!(number: '2.0~beta1').prerelease?
    assert package.versions.find_by!(number: '1.0+10').stable?
  end

  test 'version ordering follows opam numeric and nonnumeric segments' do
    ordered = %w[~~ ~ ~beta2 ~beta10 0.1 1.0~beta 1.0 1.0-test 1.0.1 1.0.10 dev trunk]
    package = @registry.packages.build(name: 'example', ecosystem: 'opam')
    versions = ordered.map { |number| package.versions.build(number: number) }

    assert_equal ordered.reverse, versions.reverse.sort.map(&:number)
    assert_equal 0, Ecosystem::Opam.compare_versions('1.01', '1.1')
  end

  test 'sync retains alternative dependency groups from raw opam metadata' do
    entry = { name: 'ocaml-variants', version: '4.14.2+options', synopsis: 'OCaml compiler', homepage: ['https://ocaml.org'] }
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: {
      data: { package: entry, packgeByVersions: { packages: [entry] } }
    }.to_json)
    stub_request(:get, 'https://opam.ocaml.org/packages/ocaml-variants/ocaml-variants.4.14.2+options/opam')
      .to_return(status: 200, body: file_fixture('opam/ocaml-variants.4.14.2+options.opam').read)

    package = @registry.sync_package('ocaml-variants').reload
    version = package.versions.sole
    formula = version.metadata.fetch('dependency_formulas').fetch('depends')
    alternatives = formula.fetch('and')[4].fetch('or')

    assert_equal 3, alternatives.length
    assert_equal({ 'or' => [{ 'name' => 'system-mingw' }, { 'name' => 'system-msvc' }] }, alternatives.first.fetch('and')[1])
    assert_equal 'os = "win32" & arch = "x86_64"', alternatives.first.fetch('and').first.fetch('constraint')
    assert version.dependencies.find_by!(package_name: 'system-mingw').optional
    assert version.dependencies.find_by!(package_name: 'system-msvc').optional
    refute version.dependencies.find_by!(package_name: 'ocaml').optional
    assert_equal 'https://github.com/ocaml/ocaml', package.repository_url
  end

  test 'a missing raw manifest aborts import rather than using flattened API dependencies' do
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: @response.to_json)
    stub_request(:get, 'https://opam.ocaml.org/packages/lwt/lwt.5.9.2/opam').to_return(status: 404)
    stub_request(:get, 'https://raw.githubusercontent.com/ocaml/opam-repository-archive/main/packages/lwt/lwt.5.9.2/opam').to_return(status: 404)

    assert_no_difference ['Package.count', 'Version.count'] do
      assert_raises(RuntimeError) { @registry.sync_package('lwt') }
    end
  end

  test 'an invalid raw manifest aborts import' do
    stub_request(:post, 'https://ocaml.org/graphql').to_return(status: 200, body: @response.to_json)
    stub_request(:get, 'https://opam.ocaml.org/packages/lwt/lwt.5.9.2/opam')
      .to_return(status: 200, body: 'depends: ["dune" | ]')

    assert_no_difference ['Package.count', 'Version.count'] do
      assert_raises(ArgumentError) { @registry.sync_package('lwt') }
    end
  end

  def stub_archive_index(packages)
    entries = packages.flat_map do |name, versions|
      versions.map { |version| { type: 'blob', path: "packages/#{name}/#{name}.#{version}/opam" } }
    end
    stub_request(:get, Ecosystem::Opam::ARCHIVE_INDEX_URL)
      .to_return(status: 200, body: { truncated: false, tree: entries }.to_json)
  end

  test 'discovery includes packages found only in the archive' do
    stub_archive_index('lwt' => ['4.1.0'], 'old-package' => ['1.0'])
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: {
      data: { allPackages: { totalPackages: 1, packages: [{ name: 'lwt', publication: 1 }] } }
    }.to_json)

    assert_equal %w[lwt old-package], @registry.all_package_names
    assert_equal %w[lwt old-package], @registry.recently_updated_package_names
  end

  test 'sync imports archived releases alongside current releases' do
    stub_archive_index('lwt' => ['4.1.0'])
    stub_archived_manifest('4.1.0', file_fixture('opam/lwt.4.1.0.archived.opam').read)
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: @response.to_json)

    package = @registry.sync_package('lwt').reload
    version = package.versions.find_by!(number: '4.1.0')

    assert_equal 4, package.versions_count
    assert_equal '6.1.2', package.latest_release_number
    assert_equal false, package.metadata['archived']
    assert version.opam_archived?
    assert_equal ['ocaml-version'], version.metadata['archive_reason']
    assert_equal 'a17a63ad3c59d7e1f745e87d85b858a34e0cda25', version.metadata['archive_commit']
    assert_equal 'https://github.com/ocsigen/lwt/archive/4.1.0.tar.gz', version.download_url
    assert_equal 'https://github.com/ocaml/opam-repository-archive/blob/main/packages/lwt/lwt.4.1.0/opam', version.registry_url
    assert_nil version.documentation_url
    assert_includes version.install_command, 'opam repository add archive'
    assert version.dependencies.exists?(package_name: 'jbuilder')
    assert_nil version.read_attribute(:published_at)
  end

  test 'sync imports a package whose every release is archived' do
    stub_archive_index('lwt' => ['4.1.0'])
    stub_archived_manifest('4.1.0', file_fixture('opam/lwt.4.1.0.archived.opam').read)
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: {
      errors: [{ message: 'No package matching lwt was found', path: ['package'] }], data: nil
    }.to_json)

    package = @registry.sync_package('lwt').reload

    assert_equal true, package.metadata['archived']
    assert_equal 'Promises, concurrency, and parallelized I/O', package.description
    assert_equal 'https://github.com/ocsigen/lwt', package.repository_url
    assert_equal 1, package.versions_count
    assert_nil package.latest_release_number
    assert_nil package.latest_version
    refute package.versions.sole.latest
    assert_equal 'active', package.read_attribute(:status)
    assert_equal 'https://github.com/ocaml/opam-repository-archive/tree/main/packages/lwt', package.registry_url
  end

  test 'a previously current release becomes archived without losing its publication date' do
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: @response.to_json)
    original = @registry.sync_package('lwt')
    version = original.versions.find_by!(number: '6.1.2')
    published_at = version.read_attribute(:published_at)

    stub_archival_transition
    package = Registry.find(@registry.id).sync_package('lwt', force: true).reload
    version.reload

    assert version.opam_archived?
    assert_equal ['maintenance-intent'], version.metadata['archive_reason']
    assert_equal published_at, version.read_attribute(:published_at)
    assert_equal '5.10.1', package.latest_release_number
    refute version.latest
    assert_equal '>= "4.14" & < "5.0"', version.dependencies.find_by!(package_name: 'ocaml').requirements
    assert_equal 3, package.versions_count
    assert_nil version.status
  end

  test 'current registry wins over an overlapping archive entry and clears archival metadata' do
    stub_archive_index('lwt' => ['6.1.2'])
    package = @registry.packages.create!(name: 'lwt', ecosystem: 'opam')
    version = package.versions.create!(number: '6.1.2', metadata: {
      archived: true, archive_reason: ['maintenance-intent'], archive_commit: 'old', depexts: 'old', retained: 'value'
    })
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: @response.to_json)

    package = @registry.sync_package('lwt', force: true).reload
    version.reload

    refute version.opam_archived?
    refute version.metadata.key?('archive_reason')
    refute version.metadata.key?('archive_commit')
    refute version.metadata.key?('depexts')
    assert_equal 'value', version.metadata['retained']
    assert_equal '6.1.2', package.latest_release_number
    assert_equal 'https://opam.ocaml.org/packages/lwt/lwt.6.1.2/', version.registry_url
    assert_not_requested :get, %r{raw\.githubusercontent\.com/ocaml/opam-repository-archive}
  end

  test 'a stale GraphQL listing falls back to the archive when a manifest moves' do
    @response['data']['packgeByVersions']['packages'].find { |entry| entry['version'] == '6.1.2' }['url']['uri'] = 'https://old.example.org/lwt.tar.gz'
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: @response.to_json)
    stub_request(:get, 'https://opam.ocaml.org/packages/lwt/lwt.6.1.2/opam').to_return(status: 404)
    stub_archived_manifest('6.1.2', file_fixture('opam/lwt.6.1.2.opam').read)

    package = @registry.sync_package('lwt').reload

    assert package.versions.find_by!(number: '6.1.2').opam_archived?
    assert_equal 'https://github.com/ocsigen/lwt/archive/refs/tags/6.1.2.tar.gz', package.versions.find_by!(number: '6.1.2').download_url
    assert_equal '5.10.1', package.latest_release_number
  end

  test 'version update worker preserves publication dates and refreshes archival state' do
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: @response.to_json)
    package = @registry.sync_package('lwt')
    version = package.versions.find_by!(number: '6.1.2')
    published_at = version.read_attribute(:published_at)
    stub_archival_transition

    UpdateVersionsWorker.new.perform(package.id)

    assert version.reload.opam_archived?
    assert_equal published_at, version.read_attribute(:published_at)
    assert_equal '5.10.1', package.reload.latest_release_number
    assert_equal '>= "4.14" & < "5.0"', version.dependencies.find_by!(package_name: 'ocaml').requirements
  end

  test 'incomplete archive discovery aborts sync without changing stored records' do
    stub_request(:get, Ecosystem::Opam::ARCHIVE_INDEX_URL)
      .to_return(status: 200, body: { truncated: true, tree: [] }.to_json)

    assert_no_difference ['Package.count', 'Version.count'] do
      assert_raises(RuntimeError) { @registry.sync_package('lwt') }
    end
  end

  def stub_archived_manifest(number, content)
    stub_request(:get, "#{Ecosystem::Opam::ARCHIVE_RAW_URL}/packages/lwt/lwt.#{number}/opam")
      .to_return(status: 200, body: content)
  end

  def stub_archival_transition
    stub_archive_index('lwt' => ['6.1.2'])
    content = file_fixture('opam/lwt.6.1.2.opam').read.sub('>= "4.14"', '>= "4.14" & < "5.0"')
    stub_archived_manifest('6.1.2', content + "\nx-reason-for-archiving: [\"maintenance-intent\"]\n")
    @response['data']['packgeByVersions']['packages'].reject! { |version| version['version'] == '6.1.2' }
    @response['data']['package']['version'] = '5.10.1'
    stub_request(:post, Ecosystem::Opam::API_URL).to_return(status: 200, body: @response.to_json)
  end
end
