require "test_helper"

class GuixTest < ActiveSupport::TestCase
  setup do
    @registry = Registry.new(default: true, name: 'guix', url: 'https://guix.gnu.org', ecosystem: 'guix')
    @ecosystem = Ecosystem::Guix.new(@registry)
    @package = Package.new(ecosystem: 'guix', name: 'hello', metadata: { 'location' => 'gnu/packages/base.scm:92' })
    @version = @package.versions.build(number: '2.12.1')
    Ecosystem::Guix.clear_packages_cache!
  end

  teardown do
    Ecosystem::Guix.clear_packages_cache!
  end

  def stub_packages_from_fixture
    json = File.read(Rails.root.join('test/fixtures/files/guix/packages.json'))
    stub_request(:get, "https://guix.gnu.org/packages.json")
      .to_return(status: 200, body: json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_packages_cache(data)
    Ecosystem::Guix.class_variable_set(:@@guix_packages_cache, data)
  end

  def scheme_fixture
    @scheme_fixture ||= File.read(Rails.root.join('test/fixtures/files/guix/base.scm'))
  end

  def stub_scheme_file_fetch
    @ecosystem.define_singleton_method(:fetch_scheme_file) { |_loc| File.read(Rails.root.join('test/fixtures/files/guix/base.scm')) }
  end

  def stub_scheme_file_fetch_nil
    @ecosystem.define_singleton_method(:fetch_scheme_file) { |_loc| nil }
  end

  test 'purl_type' do
    assert_equal 'guix', Ecosystem::Guix.purl_type
  end

  test 'sync_in_batches?' do
    assert @ecosystem.sync_in_batches?
  end

  test 'has_dependent_repos?' do
    refute @ecosystem.has_dependent_repos?
  end

  test 'registry_url' do
    url = @ecosystem.registry_url(@package, @version)
    assert_equal 'https://packages.guix.gnu.org/packages/hello/2.12.1/', url
  end

  test 'registry_url with string version' do
    url = @ecosystem.registry_url(@package, '2.10')
    assert_equal 'https://packages.guix.gnu.org/packages/hello/2.10/', url
  end

  test 'install_command' do
    cmd = @ecosystem.install_command(@package)
    assert_equal 'guix install hello', cmd
  end

  test 'install_command with version' do
    cmd = @ecosystem.install_command(@package, @version)
    assert_equal 'guix install hello@2.12.1', cmd
  end

  test 'install_command with string version' do
    cmd = @ecosystem.install_command(@package, '2.10')
    assert_equal 'guix install hello@2.10', cmd
  end

  test 'documentation_url' do
    url = @ecosystem.documentation_url(@package)
    assert_equal 'https://git.savannah.gnu.org/cgit/guix.git/tree/gnu/packages/base.scm#n92', url
  end

  test 'documentation_url without location' do
    package = Package.new(ecosystem: 'guix', name: 'test')
    assert_nil @ecosystem.documentation_url(package)
  end

  test 'documentation_url with empty metadata' do
    package = Package.new(ecosystem: 'guix', name: 'test', metadata: {})
    assert_nil @ecosystem.documentation_url(package)
  end

  test 'check_status returns nil when package exists' do
    stub_packages_cache({
      'hello' => [{ 'name' => 'hello', 'version' => '2.12.1' }]
    })

    assert_nil @ecosystem.check_status(@package)
  end

  test 'check_status returns removed when package missing' do
    stub_packages_cache({})

    assert_equal 'removed', @ecosystem.check_status(@package)
  end

  test 'packages_url' do
    assert_equal 'https://guix.gnu.org/packages.json', @ecosystem.packages_url
  end

  test 'purl' do
    purl = @ecosystem.purl(@package)
    assert_equal 'pkg:guix/hello', purl
    assert Purl.parse(purl)
  end

  test 'purl with version' do
    purl = @ecosystem.purl(@package, @version)
    assert_equal 'pkg:guix/hello@2.12.1', purl
    assert Purl.parse(purl)
  end

  test 'download_url' do
    assert_nil @ecosystem.download_url(@package, @version)
  end

  test 'all_package_names' do
    stub_packages_from_fixture

    names = @ecosystem.all_package_names
    assert_includes names, 'hello'
    assert_includes names, 'zile'
    assert_includes names, 'guile'
    assert_equal 3, names.length
  end

  test 'packages indexes by name and groups versions' do
    stub_packages_from_fixture

    pkgs = @ecosystem.packages
    assert_equal 3, pkgs.keys.length
    assert_equal 2, pkgs['hello'].length
    assert_equal 1, pkgs['zile'].length
  end

  test 'map_package_metadata' do
    stub_scheme_file_fetch

    entries = [
      {
        'name' => 'hello',
        'version' => '2.12.1',
        'synopsis' => 'Hello, GNU world: An example GNU package',
        'homepage' => 'https://www.gnu.org/software/hello/',
        'location' => 'gnu/packages/base.scm:30',
        'variable_name' => 'hello'
      },
      {
        'name' => 'hello',
        'version' => '2.10',
        'synopsis' => 'Hello, GNU world: An example GNU package',
        'homepage' => 'https://www.gnu.org/software/hello/',
        'location' => 'gnu/packages/base.scm:28',
        'variable_name' => 'hello-2.10'
      }
    ]

    mapped = @ecosystem.map_package_metadata(entries, 'hello')

    assert_equal 'hello', mapped[:name]
    assert_equal 'Hello, GNU world: An example GNU package', mapped[:description]
    assert_equal 'https://www.gnu.org/software/hello/', mapped[:homepage]
    assert_equal 'gnu/packages/base.scm:30', mapped[:metadata][:location]
    assert_equal 'hello', mapped[:metadata][:variable_name]
    assert_equal 'gpl3+', mapped[:licenses]
  end

  test 'map_package_metadata returns false for blank entries' do
    assert_equal false, @ecosystem.map_package_metadata(nil)
    assert_equal false, @ecosystem.map_package_metadata([])
  end

  test 'map_package_metadata with single entry' do
    stub_scheme_file_fetch_nil

    entry = {
      'name' => 'zile',
      'version' => '2.6.2',
      'synopsis' => 'Lightweight Emacs clone',
      'homepage' => 'https://www.gnu.org/software/zile/',
      'location' => 'gnu/packages/zile.scm:48',
      'variable_name' => 'zile'
    }

    mapped = @ecosystem.map_package_metadata(entry, 'zile')

    assert_equal 'zile', mapped[:name]
    assert_equal 'Lightweight Emacs clone', mapped[:description]
    assert_nil mapped[:licenses]
  end

  test 'map_package_metadata includes licenses when scheme file available' do
    stub_scheme_file_fetch

    entry = {
      'name' => 'grep',
      'version' => '3.11',
      'synopsis' => 'Print lines matching a pattern',
      'homepage' => 'https://www.gnu.org/software/grep/',
      'location' => 'gnu/packages/base.scm:55',
      'variable_name' => 'grep'
    }

    mapped = @ecosystem.map_package_metadata(entry, 'grep')

    assert_equal 'gpl3+', mapped[:licenses]
  end

  test 'map_package_metadata includes multiple licenses' do
    stub_scheme_file_fetch

    entry = {
      'name' => 'dual-licensed-example',
      'version' => '1.0',
      'synopsis' => 'Example package with dual license',
      'homepage' => 'https://example.org',
      'location' => 'gnu/packages/base.scm:72',
      'variable_name' => 'dual-licensed-example'
    }

    mapped = @ecosystem.map_package_metadata(entry, 'dual-licensed-example')

    assert_equal 'expat, asl2.0', mapped[:licenses]
  end

  test 'versions_metadata returns all versions' do
    stub_packages_cache({
      'hello' => [
        {
          'name' => 'hello',
          'version' => '2.12.1',
          'variable_name' => 'hello',
          'source' => [{ 'integrity' => 'sha256-jZkUKv2SV28wsM18tCqNxoCZmLnighAfahT6AFlSML0=' }]
        },
        {
          'name' => 'hello',
          'version' => '2.10',
          'variable_name' => 'hello-2.10',
          'source' => [{ 'integrity' => 'sha256-MeBmE3qWJnbon2nRtlOC3pWn732RS4y5VvQepy4PUWo=' }]
        }
      ]
    })

    versions = @ecosystem.versions_metadata({ name: 'hello' })

    assert_equal 2, versions.length
    version_numbers = versions.map { |v| v[:number] }
    assert_includes version_numbers, '2.12.1'
    assert_includes version_numbers, '2.10'

    v1 = versions.find { |v| v[:number] == '2.12.1' }
    assert_equal 'sha256-jZkUKv2SV28wsM18tCqNxoCZmLnighAfahT6AFlSML0=', v1[:integrity]
    assert_equal 'hello', v1[:metadata][:variable_name]
  end

  test 'versions_metadata returns empty when package not found' do
    stub_packages_cache({})

    versions = @ecosystem.versions_metadata({ name: 'nonexistent' })
    assert_equal [], versions
  end

  test 'versions_metadata handles missing source' do
    stub_packages_cache({
      'hello' => [
        { 'name' => 'hello', 'version' => '2.12.1', 'variable_name' => 'hello' }
      ]
    })

    versions = @ecosystem.versions_metadata({ name: 'hello' })
    assert_equal 1, versions.length
    assert_nil versions[0][:integrity]
  end

  test 'maintainers_metadata returns empty' do
    assert_equal [], @ecosystem.maintainers_metadata('hello')
  end

  test 'dependencies_metadata returns empty when package not found' do
    stub_packages_cache({})

    assert_equal [], @ecosystem.dependencies_metadata('hello', '2.12.1', nil)
  end

  test 'dependencies_metadata returns empty when no location' do
    stub_packages_cache({
      'hello' => [{ 'name' => 'hello', 'version' => '2.12.1' }]
    })

    assert_equal [], @ecosystem.dependencies_metadata('hello', '2.12.1', nil)
  end

  test 'dependencies_metadata returns empty when scheme file fetch fails' do
    stub_packages_cache({
      'hello' => [{ 'name' => 'hello', 'version' => '2.12.1', 'location' => 'gnu/packages/base.scm:30' }]
    })
    stub_scheme_file_fetch_nil

    assert_equal [], @ecosystem.dependencies_metadata('hello', '2.12.1', nil)
  end

  test 'dependencies_metadata extracts deps from scheme file' do
    stub_packages_cache({
      'grep' => [{ 'name' => 'grep', 'version' => '3.11', 'location' => 'gnu/packages/base.scm:55' }]
    })
    stub_scheme_file_fetch

    deps = @ecosystem.dependencies_metadata('grep', '3.11', nil)

    assert deps.any? { |d| d[:package_name] == 'pcre2' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'perl' && d[:kind] == 'build' }
    assert_equal 'guix', deps.first[:ecosystem]
    assert_equal '*', deps.first[:requirements]
  end

  test 'dependencies_metadata extracts propagated-inputs as runtime' do
    stub_packages_cache({
      'dual-licensed-example' => [{ 'name' => 'dual-licensed-example', 'version' => '1.0', 'location' => 'gnu/packages/base.scm:72' }]
    })
    stub_scheme_file_fetch

    deps = @ecosystem.dependencies_metadata('dual-licensed-example', '1.0', nil)

    # inputs -> runtime
    assert deps.any? { |d| d[:package_name] == 'glib' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'zlib' && d[:kind] == 'runtime' }

    # propagated-inputs -> runtime
    assert deps.any? { |d| d[:package_name] == 'libxml2' && d[:kind] == 'runtime' }

    # native-inputs -> build
    assert deps.any? { |d| d[:package_name] == 'pkg-config' && d[:kind] == 'build' }
  end

  test 'recently_updated_package_names parses atom feed' do
    atom_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry>
          <title>gnu: hello: Update to 2.12.1.</title>
        </entry>
        <entry>
          <title>gnu: guile: Update to 3.0.10.</title>
        </entry>
        <entry>
          <title>Merge branch 'staging'</title>
        </entry>
      </feed>
    XML

    stub_request(:get, "https://git.savannah.gnu.org/cgit/guix.git/atom/?h=master")
      .to_return(status: 200, body: atom_xml, headers: { 'Content-Type' => 'application/atom+xml' })

    names = @ecosystem.recently_updated_package_names
    assert_includes names, 'gnu'
    assert_equal 1, names.count('gnu')
  end

  test 'recently_updated_package_names returns empty on error' do
    stub_request(:get, "https://git.savannah.gnu.org/cgit/guix.git/atom/?h=master")
      .to_return(status: 500, body: '')

    names = @ecosystem.recently_updated_package_names
    assert_equal [], names
  end

  test 'load_packages_json handles nil response' do
    stub_request(:get, "https://guix.gnu.org/packages.json")
      .to_return(status: 200, body: 'null', headers: { 'Content-Type' => 'application/json' })

    result = @ecosystem.load_packages_json
    assert_equal({}, result)
  end

  test 'load_packages_json handles non-array response' do
    stub_request(:get, "https://guix.gnu.org/packages.json")
      .to_return(status: 200, body: '{"foo":"bar"}', headers: { 'Content-Type' => 'application/json' })

    result = @ecosystem.load_packages_json
    assert_equal({}, result)
  end

  test 'load_packages_json skips entries without name' do
    json = '[{"version":"1.0","synopsis":"No name"},{"name":"hello","version":"2.12.1"}]'
    stub_request(:get, "https://guix.gnu.org/packages.json")
      .to_return(status: 200, body: json, headers: { 'Content-Type' => 'application/json' })

    result = @ecosystem.load_packages_json
    assert_equal 1, result.keys.length
    assert_equal ['hello'], result.keys
  end

  # Scheme parsing tests

  test 'strip_scheme_comments removes line comments' do
    content = <<~SCM
      (package
        (name "hello") ; this is a comment
        ;; full line comment
        (version "1.0"))
    SCM

    stripped = @ecosystem.strip_scheme_comments(content)
    refute_includes stripped, 'this is a comment'
    refute_includes stripped, 'full line comment'
    assert_includes stripped, '(name "hello")'
    assert_includes stripped, '(version "1.0")'
  end

  test 'strip_scheme_comments handles blank input' do
    assert_equal '', @ecosystem.strip_scheme_comments(nil)
    assert_equal '', @ecosystem.strip_scheme_comments('')
  end

  test 'find_package_block extracts correct block from fixture' do
    # hello starts at line 28 in fixture (define-public hello)
    block = @ecosystem.find_package_block(scheme_fixture, 30)

    assert_includes block, '(define-public hello'
    assert_includes block, '(license license:gpl3+)'
    refute_includes block, '(define-public grep'
  end

  test 'find_package_block extracts grep block' do
    block = @ecosystem.find_package_block(scheme_fixture, 55)

    assert_includes block, '(define-public grep'
    assert_includes block, '(native-inputs (list perl))'
    assert_includes block, '(inputs (list pcre2))'
    refute_includes block, '(define-public hello'
  end

  test 'find_package_block returns nil for invalid line number' do
    assert_nil @ecosystem.find_package_block(scheme_fixture, 0)
    assert_nil @ecosystem.find_package_block(scheme_fixture, 99999)
  end

  test 'find_package_block returns nil when no define-public found' do
    content = "(let ((x 1)) x)\n" * 5
    assert_nil @ecosystem.find_package_block(content, 3)
  end

  test 'parse_guix_license with single qualified license' do
    block = '(define-public hello (package (name "hello") (license license:gpl3+)))'
    assert_equal 'gpl3+', @ecosystem.parse_guix_license(block)
  end

  test 'parse_guix_license with single unqualified license' do
    block = '(define-public hello (package (name "hello") (license gpl3+)))'
    assert_equal 'gpl3+', @ecosystem.parse_guix_license(block)
  end

  test 'parse_guix_license with multiple licenses' do
    block = '(define-public hello (package (name "hello") (license (list license:expat license:asl2.0))))'
    assert_equal 'expat, asl2.0', @ecosystem.parse_guix_license(block)
  end

  test 'parse_guix_license returns nil when no license' do
    block = '(define-public hello (package (name "hello")))'
    assert_nil @ecosystem.parse_guix_license(block)
  end

  test 'parse_guix_license returns nil for blank input' do
    assert_nil @ecosystem.parse_guix_license(nil)
    assert_nil @ecosystem.parse_guix_license('')
  end

  test 'parse_guix_license ignores comments containing license' do
    block = <<~SCM
      (define-public hello
        (package
          (name "hello")
          ; (license gpl2)
          (license license:expat)))
    SCM
    assert_equal 'expat', @ecosystem.parse_guix_license(block)
  end

  test 'parse_guix_dependencies extracts inputs' do
    block = <<~SCM
      (define-public grep
        (package
          (name "grep")
          (native-inputs (list perl))
          (inputs (list pcre2))
          (license gpl3+)))
    SCM

    deps = @ecosystem.parse_guix_dependencies(block)

    assert deps.any? { |d| d[:package_name] == 'pcre2' && d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'perl' && d[:kind] == 'build' }
    assert_equal 2, deps.length
  end

  test 'parse_guix_dependencies extracts propagated-inputs as runtime' do
    block = <<~SCM
      (define-public example
        (package
          (name "example")
          (propagated-inputs (list libxml2 glib))
          (license expat)))
    SCM

    deps = @ecosystem.parse_guix_dependencies(block)

    assert deps.all? { |d| d[:kind] == 'runtime' }
    assert deps.any? { |d| d[:package_name] == 'libxml2' }
    assert deps.any? { |d| d[:package_name] == 'glib' }
  end

  test 'parse_guix_dependencies returns empty for no inputs' do
    block = <<~SCM
      (define-public hello
        (package
          (name "hello")
          (license gpl3+)))
    SCM

    assert_equal [], @ecosystem.parse_guix_dependencies(block)
  end

  test 'parse_guix_dependencies returns empty for blank input' do
    assert_equal [], @ecosystem.parse_guix_dependencies(nil)
    assert_equal [], @ecosystem.parse_guix_dependencies('')
  end

  test 'parse_guix_dependencies filters builtins' do
    block = <<~SCM
      (define-public example
        (package
          (name "example")
          (inputs (list glib))
          (license expat)))
    SCM

    deps = @ecosystem.parse_guix_dependencies(block)
    dep_names = deps.map { |d| d[:package_name] }

    refute_includes dep_names, 'list'
    assert_includes dep_names, 'glib'
  end

  test 'extract_scheme_list extracts identifiers from list form' do
    content = '(inputs (list pcre2 zlib glib))'
    names = @ecosystem.extract_scheme_list(content, 'inputs')

    assert_includes names, 'pcre2'
    assert_includes names, 'zlib'
    assert_includes names, 'glib'
  end

  test 'extract_scheme_list handles multiline list' do
    content = <<~SCM
      (inputs
        (list pcre2
              zlib
              glib))
    SCM

    names = @ecosystem.extract_scheme_list(content, 'inputs')
    assert_includes names, 'pcre2'
    assert_includes names, 'zlib'
    assert_includes names, 'glib'
  end

  test 'extract_scheme_list returns empty when attr not found' do
    content = '(native-inputs (list perl))'
    names = @ecosystem.extract_scheme_list(content, 'inputs')
    assert_equal [], names
  end

  test 'extract_scheme_list returns empty for empty list' do
    content = '(inputs (list))'
    names = @ecosystem.extract_scheme_list(content, 'inputs')
    assert_equal [], names
  end

  test 'guix_builtin? identifies builtins' do
    assert @ecosystem.guix_builtin?('list')
    assert @ecosystem.guix_builtin?('modify-inputs')
    assert @ecosystem.guix_builtin?('append')
    assert @ecosystem.guix_builtin?('replace')
    assert @ecosystem.guix_builtin?('delete')

    refute @ecosystem.guix_builtin?('glib')
    refute @ecosystem.guix_builtin?('pcre2')
    refute @ecosystem.guix_builtin?('perl')
  end

  test 'fetch_scheme_file constructs correct url' do
    stub_request(:get, "https://raw.githubusercontent.com/Millak/guix/master/gnu/packages/base.scm")
      .to_return(status: 200, body: '(define-public hello ...)')

    result = @ecosystem.fetch_scheme_file('gnu/packages/base.scm:92')
    assert_equal '(define-public hello ...)', result
  end

  test 'fetch_scheme_file returns nil on error' do
    stub_request(:get, "https://raw.githubusercontent.com/Millak/guix/master/gnu/packages/base.scm")
      .to_return(status: 404, body: '')

    result = @ecosystem.fetch_scheme_file('gnu/packages/base.scm:92')
    assert_nil result
  end
end
