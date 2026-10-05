require "test_helper"

class OctaveTest < ActiveSupport::TestCase
  INDEX_URL = 'https://packages.octave.org/packages.json'

  setup do
    @registry = Registry.new(default: true, name: 'packages.octave.org', url: 'https://packages.octave.org', ecosystem: 'octave')
    @ecosystem = Ecosystem::Octave.new(@registry)
    @package = Package.new(ecosystem: 'octave', name: 'csg-toolkit')
    @version = @package.versions.build(number: '1.4.3', metadata: { 'download_url' => 'https://github.com/pr0m1th3as/csg-toolkit/archive/refs/tags/release-1.4.3.tar.gz' })
  end

  def stub_index
    stub_request(:get, INDEX_URL).to_return(status: 200, body: file_fixture('octave/packages.json'), headers: { 'ETag' => '"abc"', 'Last-Modified' => 'Fri, 02 Oct 2026 06:36:50 GMT' })
  end

  def package_metadata(name)
    stub_index
    @ecosystem.package_metadata(name)
  end

  test 'registry_url' do
    assert_equal 'https://packages.octave.org/csg-toolkit', @ecosystem.registry_url(@package)
  end

  test 'download_url' do
    assert_equal 'https://github.com/pr0m1th3as/csg-toolkit/archive/refs/tags/release-1.4.3.tar.gz', @ecosystem.download_url(@package, @version)
    assert_nil @ecosystem.download_url(@package)
  end

  test 'install_command uses the release archive' do
    assert_equal 'pkg install "https://github.com/pr0m1th3as/csg-toolkit/archive/refs/tags/release-1.4.3.tar.gz"', @ecosystem.install_command(@package, @version)
  end

  test 'install_command is nil when the release url is not an archive' do
    version = @package.versions.build(number: '7.2', metadata: { 'download_url' => 'https://www.dynare.org/download/' })
    assert_nil @ecosystem.install_command(@package, version)
  end

  test 'purl' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:octave/csg-toolkit@1.4.3', purl
    assert Purl.parse(purl)
  end

  test 'all_package_names follows the index redirect' do
    stub_request(:get, INDEX_URL).to_return(status: 307, headers: { 'Location' => 'https://gnu-octave.github.io/packages/packages.json' })
    stub_request(:get, 'https://gnu-octave.github.io/packages/packages.json').to_return(status: 200, body: file_fixture('octave/packages.json'))

    assert_equal %w[apa coder csg-toolkit dynare json], @ecosystem.all_package_names
  end

  test 'all_package_names is empty when the index is unavailable' do
    stub_request(:get, INDEX_URL).to_return(status: 503)
    assert_equal [], @ecosystem.all_package_names
  end

  test 'recently_updated_package_names orders by latest release date' do
    stub_index
    assert_equal %w[dynare apa coder csg-toolkit json], @ecosystem.recently_updated_package_names
  end

  test 'package_index reuses the cached body when the index is not modified' do
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(cache)
    stub_index
    assert_equal 5, @ecosystem.package_index.size

    not_modified = stub_request(:get, INDEX_URL)
      .with(headers: { 'If-None-Match' => '"abc"', 'If-Modified-Since' => 'Fri, 02 Oct 2026 06:36:50 GMT' })
      .to_return(status: 304)
    assert_equal 5, Ecosystem::Octave.new(@registry).package_index.size
    assert_requested not_modified
  end

  test 'package_metadata' do
    metadata = package_metadata('csg-toolkit')

    assert_equal 'csg-toolkit', metadata[:name]
    assert_match(/cross-sectional geometric properties of long bones/, metadata[:description])
    assert_equal 'https://pr0m1th3as.github.io/csg-toolkit/', metadata[:homepage]
    assert_equal 'GPL-3.0-or-later', metadata[:licenses]
    assert_equal 'https://github.com/pr0m1th3as/csg-toolkit', metadata[:repository_url]
    assert_equal [{ 'name' => 'Andreas Bertsatos', 'contact' => 'abertsatos@biol.uoa.gr' }], metadata[:metadata][:maintainers]
    assert_equal 'https://github.com/pr0m1th3as/csg-toolkit/issues', metadata[:metadata][:issues_url]
  end

  test 'package_metadata returns false for an unknown package' do
    refute package_metadata('missing')
  end

  test 'versions_metadata skips dev entries and keeps requirements separate' do
    versions = @ecosystem.versions_metadata(package_metadata('apa'))

    assert_equal ['1.2.2'], versions.map { |version| version[:number] }
    version = versions.first
    assert_equal '2026-05-03', version[:published_at]
    assert_equal 'sha256-1df4afc7db1a3f425c22d9d50f864f75f6bff4d3d7dbccce0b6622b29b13bb96', version[:integrity]
    assert_equal 'https://github.com/gnu-octave/pkg-apa/archive/refs/tags/v1.2.2.tar.gz', version[:metadata][:download_url]
    assert_equal ['>= 9.1.0'], version[:metadata][:octave_requirements]
    assert_equal({ 'ubuntu2604' => ['libmpfr-dev'] }, version[:metadata][:system_requirements])
  end

  test 'versions_metadata keeps every interpreter constraint' do
    version = @ecosystem.versions_metadata(package_metadata('json')).first

    assert_equal ['>= 5.1.0', '< 7.0.0'], version[:metadata][:octave_requirements]
    refute version[:metadata].key?(:system_requirements)
  end

  test 'versions_metadata leaves integrity blank without a checksum' do
    versions = @ecosystem.versions_metadata(package_metadata('dynare'))

    assert_equal %w[7.2 7.1], versions.map { |version| version[:number] }
    assert_nil versions.first[:integrity]
    assert_equal versions.first.keys, versions.last.keys
  end

  test 'dependencies_metadata returns only Octave package dependencies' do
    deps = @ecosystem.dependencies_metadata('csg-toolkit', '1.4.3', package_metadata('csg-toolkit'))

    assert_equal %w[statistics datatypes io pkg], deps.map { |dep| dep[:package_name] }
    assert_equal ['>= 1.7.4', '>= 1.0.1', '>= 2.6.4', '*'], deps.map { |dep| dep[:requirements] }
    deps.each do |dep|
      assert_equal 'runtime', dep[:kind]
      assert_equal 'octave', dep[:ecosystem]
    end
  end

  test 'dependencies_metadata is empty for an interpreter only release' do
    assert_equal [], @ecosystem.dependencies_metadata('dynare', '7.2', package_metadata('dynare'))
  end

  test 'dependencies_metadata is empty for an unknown version' do
    assert_equal [], @ecosystem.dependencies_metadata('apa', 'dev', package_metadata('apa'))
  end

  test 'parse_dependencies combines constraints on the same package' do
    result = @ecosystem.parse_dependencies(['octave (>= 6.1.0)', 'io (>= 2.0)', 'io (< 3)', 'nurbs (>=1.3)'])

    assert_equal ['>= 6.1.0'], result[:interpreter]
    assert_equal({ 'io' => ['>= 2.0', '< 3'], 'nurbs' => ['>=1.3'] }, result[:packages])
  end

  test 'maintainers_metadata' do
    stub_index

    assert_equal [{ uuid: 'kai.ohlhus@gmail.com', name: 'Kai T. Ohlhus', email: 'kai.ohlhus@gmail.com', url: nil }], @ecosystem.maintainers_metadata('apa')
    assert_equal [{ uuid: 'https://github.com/shsajjadi', name: 'Seyyed Hossein Sajjadi', email: nil, url: 'https://github.com/shsajjadi' }], @ecosystem.maintainers_metadata('coder')
    assert_equal [], @ecosystem.maintainers_metadata('missing')
  end

  test 'check_status' do
    stub_index

    assert_nil @ecosystem.check_status(@package)
    assert_equal 'removed', @ecosystem.check_status(Package.new(ecosystem: 'octave', name: 'missing'))
  end

  test 'check_status does not mark packages removed when the index is unavailable' do
    stub_request(:get, INDEX_URL).to_return(status: 503)
    assert_equal false, @ecosystem.check_status(@package)
  end

  test 'sync_package stores releases and package dependencies' do
    registry = Registry.create!(default: true, name: 'packages.octave.org', url: 'https://packages.octave.org', ecosystem: 'octave')
    stub_index

    registry.sync_package('csg-toolkit', force: true)

    package = registry.packages.find_by!(name: 'csg-toolkit')
    assert_equal %w[1.4.2 1.4.3], package.versions.pluck(:number).sort
    version = package.versions.find_by!(number: '1.4.3')
    assert_equal ['>= 9.1.0'], version.metadata['octave_requirements']
    assert_equal %w[datatypes io pkg statistics], version.dependencies.pluck(:package_name).sort
    assert_equal ['abertsatos@biol.uoa.gr'], package.maintainers.pluck(:email)
  end
end
