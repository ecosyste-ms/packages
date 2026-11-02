require 'test_helper'
require 'rake'
require 'stringio'
require_relative '../../lib/corpus/export'
require_relative '../../lib/corpus/upload'

class CorpusRakeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('exports:corpus')
    @dir = Dir.mktmpdir
    @env = ENV.to_h
    %w[UPLOAD SOURCE ASSIGNMENTS OUTPUT FILE S3_ENDPOINT S3_BUCKET S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN S3_PREFIX BATCH_SIZE TARGET SEED HEAD_LIMIT CENSUS_LIMIT REGISTRY_FLOOR REGISTRY_CAP].each { |key| ENV.delete(key) }
    ENV['OUTPUT'] = File.join(@dir, 'corpus.tar.gz')
    @created_packages = []
    @created_registries = []
    @created_maintainers = []
  end

  teardown do
    Maintainership.where(package_id: @created_packages).delete_all
    Maintainer.where(id: @created_maintainers).delete_all
    Package.where(id: @created_packages).delete_all
    Registry.where(id: @created_registries).delete_all
    ENV.replace(@env)
    FileUtils.remove_entry(@dir)
  end

  def fixture(records)
    source = File.join(@dir, 'packages.ndjson.gz')
    Zlib::GzipWriter.open(source) { |gz| records.each { |row| gz.puts(JSON.generate(row)) } }
    rows = records.map { |p| {'package_id' => p.fetch('package_id'), 'project_id' => 'project:curl', 'previous_project_id' => 'project:curl', 'display_name' => 'curl', 'reason' => 'distribution_release'} }
    assignments = File.join(@dir, 'assignments.ndjson.gz')
    Zlib::GzipWriter.open(assignments) { |gz| rows.each { |row| gz.puts(JSON.generate(row)) } }
    manifest = {packages: records.size, projects: 1, assignments_file: 'assignments.ndjson.gz', assignments_sha256: Digest::SHA256.file(assignments).hexdigest, source_package_sha256: Digest::SHA256.file(source).hexdigest, source_corpus_sha256: 'a' * 64, as_of: '2026-10-31T00:00:00Z'}
    ENV['ASSIGNMENTS'] = File.join(@dir, 'assignment-manifest.json')
    File.write(ENV['ASSIGNMENTS'], JSON.generate(manifest))
    ENV['SOURCE'] = source
    records
  end

  def record(id, status: 'active', purl: "pkg:nix/curl?channel=#{id}")
    {'package_id' => id, 'name' => 'curl', 'ecosystem' => 'nixpkgs', 'namespace' => nil, 'status' => status, 'purl' => purl,
      'registry' => {'id' => id, 'name' => "nixpkgs-#{id}"}, 'signals' => {'downloads' => nil, 'dependent_packages_count' => 0},
      'repository' => {'id' => 10}, 'description' => 'Transfer data', 'activity' => {}}
  end

  def invoke_export
    capture_io { Rake::Task['exports:corpus'].execute }
    files = nil
    Zlib::GzipReader.open(ENV.fetch('OUTPUT')) do |gz|
      Gem::Package::TarReader.new(gz) { |tar| files = tar.to_h { |entry| [entry.full_name, entry.read] } }
    end
    files
  end

  def json_rows(files, name)
    Zlib::GzipReader.new(StringIO.new(files.fetch(name))).each_line.map { |line| JSON.parse(line) }
  end

  def registry(name, ecosystem, **attributes)
    result = Registry.create!({name: name, ecosystem: ecosystem, url: "https://#{name}"}.merge(attributes))
    @created_registries << result.id
    result
  end

  def package(registry, name, **attributes)
    id = Package.insert!({registry_id: registry.id, ecosystem: registry.ecosystem, name: name, status: 'active',
      description: 'A package used by the export regression cases', normalized_licenses: ['MIT'], keywords_array: ['network'],
      downloads: 0, dependent_packages_count: 0, dependent_repos_count: 0}.merge(attributes)).rows.first.first
    @created_packages << id
    id
  end

  test 'rake generates a complete searchable corpus from the database without any input files' do
    nix_a = registry('nixpkgs-24.11', 'nixpkgs', version: '24.11', url: 'https://channels.nixos.org/nixos-24.11')
    nix_b = registry('nixpkgs-unstable', 'nixpkgs', version: 'unstable', url: 'https://channels.nixos.org/nixos-unstable')
    cargo = registry('crates.io', 'cargo')
    npm = registry('npmjs.org', 'npm')
    unknown = registry('unknown.example', 'unknown')
    curl_repo = {'id' => 123, 'html_url' => 'https://github.com/curl/curl', 'full_name' => 'curl/curl', 'description' => 'Transfer data using URL syntax', 'language' => 'C', 'license' => 'curl', 'topics' => ['http'], 'stargazers_count' => 500}
    curls = [nix_a, nix_b].map { |r| package(r, 'curl', repo_metadata: curl_repo, repository_url: 'https://curl.se', language: 'C', downloads: 100, rankings: {'downloads' => 0.01}) }
    variant = package(nix_a, 'curlWithGnuTls', repo_metadata: curl_repo, repository_url: 'https://curl.se')
    wrapper = package(cargo, 'curl', repo_metadata: {'id' => 124, 'html_url' => 'https://github.com/alexcrichton/curl-rust'}, repository_url: 'https://github.com/alexcrichton/curl-rust')
    trezor_repo = {'id' => 125, 'html_url' => 'https://github.com/trezor/trezor-firmware', 'full_name' => 'trezor/trezor-firmware'}
    trezor = package(npm, 'python-trezor', repo_metadata: trezor_repo, repository_url: trezor_repo['html_url'])
    jpeg = package(cargo, 'trezor-tjpgdec', repo_metadata: trezor_repo, repository_url: trezor_repo['html_url'])
    no_purl = package(unknown, 'missing-purl', downloads: nil)
    removed = package(npm, 'removed-package', status: 'Removed', downloads: 999999)
    ENV['TARGET'] = '100'
    assert_nil ENV['ASSIGNMENTS']
    assert_nil ENV['SOURCE']
    files = invoke_export
    packages = json_rows(files, 'packages.ndjson.gz')
    assignments = json_rows(files, 'assignments.ndjson.gz').to_h { |a| [a['package_id'], a['project_id']] }
    assert_equal (@created_packages - [removed]).sort, packages.map { |p| p['package_id'] }.sort
    assert_equal assignments[curls.first], assignments[curls.last]
    assert_not_equal assignments[curls.first], assignments[variant]
    assert_not_equal assignments[curls.first], assignments[wrapper]
    assert_not_equal assignments[trezor], assignments[jpeg]
    compact = json_rows(files, 'projects.ndjson.gz').to_h { |p| [p['id'], p] }
    group = compact.fetch(assignments[curls.first])
    assert_equal curls.sort, group['identifiers']['package_ids'].sort
    assert_equal 2, group['identifiers']['package_purls'].map(&:last).uniq.size
    assert_includes group['aliases'], 'network'
    assert_includes group['filters']['language'], 'c'
    assert_equal 100, group['ranking']['downloads_max']
    assert_equal 0.5, group['ranking']['popularity']
    assert_nil compact.fetch(assignments[no_purl]).dig('public', 'packages', 0, 'purl')
    assert_nil packages.find { |p| p['package_id'] == no_purl }.dig('signals', 'downloads')
    corpus = JSON.parse(files.fetch('corpus.json'))
    assert_equal compact.keys.sort, corpus['projects'].map { |p| p['id'] }.sort
    assert_equal compact.keys.sort, corpus['metadata'].keys.sort
    assert_not JSON.parse(files['assignment-manifest.json']).key?('source_corpus_sha256')
    manifest = JSON.parse(files['manifest.json'])
    assert_equal 100, manifest['selection']['target']
    manifest['files'].each { |name, info| assert_equal info['sha256'], Digest::SHA256.hexdigest(files.fetch(name)) }
  end

  test 'database selection bounds every signal query and records prefix truncation' do
    npm = registry('npmjs.org', 'npm', packages_count: 100_000)
    505.times do |i|
      package(npm, "candidate-#{i}", downloads: i + 1, dependent_packages_count: i + 1,
        dependent_repos_count: i + 1, docker_downloads_count: i + 1, repo_metadata: {'stargazers_count' => i + 1, 'forks_count' => i + 1})
    end
    ENV.update('TARGET' => '20', 'HEAD_LIMIT' => '500', 'CENSUS_LIMIT' => '0')
    database = Corpus::Database.new
    database.define_singleton_method(:read) do |sql, **options|
      if options[:sample]
        @selection_sample ||= super(sql, **options)
      else
        super(sql, **options)
      end
    end
    Corpus::Database.stubs(:new).returns(database)
    statements = []
    listener = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }
    files = ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') { invoke_export }
    selection = JSON.parse(files.fetch('selection.json'))
    assert_equal 20, selection['selected']
    signals = selection.fetch('signals').select { |r| r['registry_id'] == npm.id }
    assert_equal Corpus::Selection::METRICS.sort, signals.map { |r| r['signal'] }.sort
    assert signals.all? { |r| r['truncated'] && r['observed_packages'] == 500 && r['observed_total'] == (6..505).sum }
    assert statements.any? { |sql| sql.include?('TABLESAMPLE SYSTEM') && sql.include?('REPEATABLE') }
    assert_equal 6, statements.count { |sql| sql.start_with?('DECLARE corpus_rows') && sql.include?('ORDER BY') && sql.end_with?('LIMIT 501') }
    assert_operator statements.count { |sql| sql == 'FETCH FORWARD 250 FROM corpus_rows' }, :>=, 24
    assert_not statements.any? { |sql| sql.match?(/\bFROM "?versions"?\b/i) }
    first_ids = json_rows(files, 'packages.ndjson.gz').map { |p| p['package_id'] }
    ENV['OUTPUT'] = File.join(@dir, 'repeat.tar.gz')
    assert_equal first_ids, json_rows(invoke_export, 'packages.ndjson.gz').map { |p| p['package_id'] }
  end

  test 'cursor reads enforce row limits and release the transaction after failure' do
    database = Corpus::Database.new
    sql = 'SELECT generate_series(1, 251) AS id'
    error = assert_raises(RuntimeError) { database.read(sql, limit: 250, cursor: true) }
    assert_match(/row limit/, error.message)
    assert_equal (1..251).to_a, database.read(sql, limit: 251, cursor: true).map { |row| row['id'] }
  end

  test 'rake groups corroborated stored identities and rejects homepage only and conflicting repositories' do
    npm = registry('npmjs.org', 'npm')
    cargo = registry('crates.io', 'cargo')
    alpine = registry('alpine-v3.20', 'alpine', version: 'v3.20', url: 'https://pkgs.alpinelinux.org/packages?branch=v3.20')
    description = 'An implementation of the example document transfer protocol'
    exact = [npm, cargo].map { |r| package(r, 'transfer', description: description, homepage: 'https://transfer.example/') }
    homepage_only = package(cargo, 'wrapper', description: 'A language wrapper', homepage: 'http://www.transfer.example')
    conflicts = [npm, cargo].each_with_index.map do |r, index|
      package(r, 'conflict', description: description, homepage: 'https://conflict.example',
        repository_url: "https://github.com/author#{index}/conflict", repo_metadata: {'id' => 300 + index, 'html_url' => "https://github.com/author#{index}/conflict"})
    end
    origin = %w[sqlite sqlite-libs].map do |name|
      package(alpine, name, description: name, homepage: 'https://sqlite.org', metadata: {'origin' => 'sqlite', 'architecture' => 'x86_64'})
    end
    maintainers = [npm, cargo].map do |r|
      id = Maintainer.insert!({registry_id: r.id, login: 'author', email: 'author@example.org'}).rows.first.first
      @created_maintainers << id
      id
    end
    maintained = [npm, cargo].each_with_index.map do |r, index|
      id = package(r, 'maintained', description: description, maintainers_count: 1)
      Maintainership.insert!({package_id: id, maintainer_id: maintainers[index]})
      id
    end
    alias_repo = {'id' => 401, 'html_url' => 'https://github.com/new-owner/renamed', 'previous_names' => ['old-owner/renamed']}
    aliases = [npm, cargo].zip(%w[old-owner new-owner]).map do |r, owner|
      package(r, 'renamed', repository_url: "https://github.com/#{owner}/renamed", repo_metadata: alias_repo)
    end
    ENV['TARGET'] = '100'
    files = invoke_export
    groups = json_rows(files, 'assignments.ndjson.gz').to_h { |a| [a['package_id'], a['project_id']] }
    [exact, origin, maintained, aliases].each { |pair| assert_equal groups[pair.first], groups[pair.last] }
    assert_not_equal groups[exact.first], groups[homepage_only]
    assert_not_equal groups[conflicts.first], groups[conflicts.last]
    exported = json_rows(files, 'packages.ndjson.gz').find { |p| p['package_id'] == maintained.first }
    assert_equal 'author@example.org', exported.dig('maintainers', 0, 'email')
    assert_equal 1, JSON.parse(files['identity.json']).dig('rejected_components', 'repository_conflict')
  end

  test 'rake snapshot export preserves relationships and nulls and excludes removed packages' do
    original = fixture([record(1), record(2, purl: nil), record(3, status: 'Removed')])
    files = invoke_export
    assert_equal original.first(2), json_rows(files, 'packages.ndjson.gz')
    assert_equal [1, 2], json_rows(files, 'projects.ndjson.gz').first.fetch('package_ids')
    assert_equal [1, 2], json_rows(files, 'assignments.ndjson.gz').map { |p| p['package_id'] }
    manifest = JSON.parse(files.fetch('manifest.json'))
    assert_equal 2, manifest['records']
    assert_equal 1, manifest['null_counts']['purl']
    assert_equal 2, manifest['null_counts']['signals.downloads']
    assert_nil manifest['null_counts']['signals.dependent_packages_count']
    manifest['files'].each { |name, info| assert_equal info['sha256'], Digest::SHA256.hexdigest(files.fetch(name)) }
    assert_equal [{'package_id' => 3, 'reason' => 'removed'}], JSON.parse(files.fetch('excluded.json'))
    before = File.binread(ENV['OUTPUT'])
    assert_raises(ArgumentError) { invoke_export }
    assert_equal before, File.binread(ENV['OUTPUT'])
  end

  test 'compact projections preserve package identities and project output' do
    original = fixture([record(1), record(2)])
    original.each do |p|
      p['repository'].merge!('tags' => [{'name' => 'v1', 'sha' => 'large tag history'}], 'scorecard' => {'checks' => ['large scorecard']})
      p['language'] = 'C'
      p['normalized_licenses'] = ['MIT']
      p['rankings'] = {'downloads' => 0.2, 'dependent_repos_count' => 0.5, 'unused' => 'large ranking detail'}
      p['signals'].merge!('downloads' => 100, 'dependent_repos_count' => 20, 'docker_downloads_count' => 999)
      p['activity'] = {'latest_release_number' => '8.0', 'versions_updated_at' => '2026-01-01'}
      p['registry'].merge!('ecosystem' => 'nixpkgs', 'url' => 'https://example.org', 'metadata' => {'codename' => 'stable', 'unused' => 'large registry detail'})
      p['maintainers'] = [{'id' => 9, 'registry_id' => 1, 'email' => 'author@example.org', 'url' => 'https://github.com/author', 'login' => 'author'}]
    end
    fixture(original)
    files = invoke_export
    expected_packages = original.map { |p| p.merge('repository' => p['repository'].slice(*Corpus::Export::REPOSITORY_FIELDS)) }
    assert_equal expected_packages, json_rows(files, 'packages.ndjson.gz')
    assert original.all? { |p| p['repository'].key?('tags') }
    expected = Dir.mktmpdir('expected-', @dir)
    rows = original.each_with_index.map { |p, i| p.merge('source_line' => i + 1) }
    assignments = json_rows(files, 'assignments.ndjson.gz')
    Corpus::Projects.new(rows: rows, assignments: assignments, as_of: '2026-10-31T00:00:00Z').write(expected, JSON.parse(files['manifest.json']).fetch('sha256'))
    assert_equal File.binread(File.join(expected, 'projects.ndjson.gz')), files['projects.ndjson.gz']
    assert_equal JSON.parse(File.read(File.join(expected, 'corpus.json'))), JSON.parse(files['corpus.json'])
    exporter = Corpus::Export.allocate
    projected = exporter.projection(original.first)
    assert_equal ['downloads', 'dependent_repos_count'].sort, projected['signals'].keys.sort
    assert_equal ['latest_release_number'], projected['activity'].keys
    assert_equal({'codename' => 'stable'}, projected.dig('registry', 'metadata'))
    assert_same projected['registry'], exporter.projection(original.first)['registry']
    changed = Marshal.load(Marshal.dump(original.first))
    changed['registry']['metadata']['codename'] = 'testing'
    assert_not_same projected['registry'], exporter.projection(changed)['registry']
  end

  test 'database export fetches compact repository metadata without changing stored records' do
    npm = registry('npmjs.org', 'npm')
    repository = {'id' => 77, 'html_url' => 'https://github.com/example/library', 'full_name' => 'example/library',
      'description' => 'An HTTP client', 'topics' => ['http', nil], 'archived' => false, 'fork' => false,
      'stargazers_count' => 10, 'forks_count' => 0, 'tags' => [{'name' => 'v1'}], 'scorecard' => {'checks' => ['details']}}
    id = package(npm, 'library', repository_url: repository['html_url'], repo_metadata: repository)
    empty = package(npm, 'empty', repo_metadata: {})
    scalar = package(npm, 'scalar', repo_metadata: ['unexpected'])
    missing = package(npm, 'missing', repo_metadata: nil)
    statements = []
    listener = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }
    files = ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') { invoke_export }
    rows = json_rows(files, 'packages.ndjson.gz').to_h { |r| [r['package_id'], r] }
    assert_equal repository.slice(*Corpus::Export::REPOSITORY_FIELDS), rows[id]['repository']
    assert_equal 10, rows[id].dig('signals', 'stargazers_count')
    assert_equal 0, rows[id].dig('signals', 'forks_count')
    assert_equal Package.find(id).purl, rows[id]['purl']
    assert_equal({}, rows[empty]['repository'])
    assert_nil rows[scalar]['repository']
    assert_nil rows[missing]['repository']
    assert_equal repository, Package.find(id).repo_metadata
    assert statements.any? { |sql| sql.start_with?('SELECT') && sql.include?('json_each(repo_metadata)') }
  end

  test 'known removals are excluded even when the snapshot still says active' do
    fixture([record(1), record(2)])
    manifest = JSON.parse(File.read(ENV['ASSIGNMENTS'])).merge('known_newly_removed_package_ids' => [2])
    File.write(ENV['ASSIGNMENTS'], JSON.generate(manifest))
    assert_equal [1], json_rows(invoke_export, 'packages.ndjson.gz').map { |p| p['package_id'] }
  end

  test 'a mismatched snapshot fails without a final archive or upload' do
    fixture([record(1)])
    File.open(ENV['SOURCE'], 'ab') { |f| f.write('changed') }
    assert_match(/checksum/, assert_raises(RuntimeError) { invoke_export }.message)
    assert_not File.exist?(ENV['OUTPUT'])
  end

  test 'database export uses bounded read only batches and service purls without querying versions' do
    registry = Registry.create!(name: "corpus-test-#{SecureRandom.hex(6)}", ecosystem: 'npm', url: 'https://registry.npmjs.org')
    @created_registries << registry.id
    [nil, 'removed', 'active'].each_with_index do |status, index|
      id = Package.insert!({name: "corpus-test-#{index}", registry_id: registry.id, ecosystem: 'npm', status: status,
        downloads: nil, dependent_packages_count: 0, repo_metadata: {'id' => 11, 'forks_count' => 0}}).rows.first.first
      @created_packages << id
    end
    fixture(@created_packages.map { |id| record(id) })
    ENV.delete('SOURCE')
    ENV['BATCH_SIZE'] = '1'
    statements = []
    listener = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }
    files = ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') { invoke_export }
    rows = json_rows(files, 'packages.ndjson.gz')
    assert_equal @created_packages.values_at(0, 2), rows.map { |p| p['package_id'] }
    assert_equal Package.find(@created_packages.first).purl, rows.first['purl']
    assert_nil rows.first.dig('signals', 'downloads')
    assert_equal 0, rows.first.dig('signals', 'forks_count')
    assert_operator statements.count { |sql| sql == 'SET TRANSACTION READ ONLY' }, :>=, 3
    assert_operator statements.count { |sql| sql.start_with?('EXPLAIN (FORMAT JSON)') }, :>=, 3
    assert_not statements.any? { |sql| sql.match?(/\bFROM "?versions"?\b/i) }
    assert_equal 3, Package.where(id: @created_packages).count
    assert_equal 'database', JSON.parse(files['manifest.json'])['source']
  end

  test 'upload task streams the archive to an escaped R2 key with signed headers' do
    path = File.join(@dir, 'upload.tar.gz')
    File.binwrite(path, "archive\x00bytes")
    ENV.update('FILE' => path, 'S3_ENDPOINT' => 'https://account.r2.cloudflarestorage.com', 'S3_BUCKET' => 'exports',
      'AWS_ACCESS_KEY_ID' => 'example-access', 'AWS_SECRET_ACCESS_KEY' => 'example-secret', 'AWS_SESSION_TOKEN' => 'example-token', 'S3_PREFIX' => 'test data')
    sha = Digest::SHA256.file(path).hexdigest
    request = stub_request(:put, "https://account.r2.cloudflarestorage.com/exports/test%20data/#{sha}.tar.gz").with do |req|
      req.body == File.binread(path) && req.headers['X-Amz-Content-Sha256'] == sha &&
        req.headers['X-Amz-Security-Token'] == 'example-token' &&
        req.headers['Authorization'].include?('/auto/s3/aws4_request')
    end.to_return(status: 200)
    capture_io { Rake::Task['exports:upload_corpus'].execute }
    assert_requested request
  end

  test 'missing selected packages fail without publishing a partial archive' do
    fixture([record(1), record(2)])
    Zlib::GzipWriter.open(ENV['SOURCE']) { |gz| gz.puts(JSON.generate(record(1))) }
    manifest = JSON.parse(File.read(ENV['ASSIGNMENTS']))
    manifest['source_package_sha256'] = Digest::SHA256.file(ENV['SOURCE']).hexdigest
    File.write(ENV['ASSIGNMENTS'], JSON.generate(manifest))
    assert_match(/Selected packages missing/, assert_raises(RuntimeError) { invoke_export }.message)
    assert_not File.exist?(ENV['OUTPUT'])
  end

  test 'expensive sequential plans are rejected before fetching package rows' do
    fixture([record(1)])
    ENV.delete('SOURCE')
    connection = Package.connection
    connection.stubs(:select_value).with(regexp_matches(/\AEXPLAIN/)).returns(JSON.generate([{'Plan' => {'Node Type' => 'Limit', 'Total Cost' => 10, 'Plans' => [{'Node Type' => 'Seq Scan', 'Total Cost' => 25000, 'Plan Rows' => 1000000}]}}]))
    assert_match(/scan a large table sequentially/, assert_raises(RuntimeError) { invoke_export }.message)
    assert_not File.exist?(ENV['OUTPUT'])
  end

  test 'failed upload retains the completed local archive and does not follow redirects' do
    fixture([record(1)])
    ENV.update('UPLOAD' => 'true', 'S3_ENDPOINT' => 'https://account.r2.cloudflarestorage.com', 'S3_BUCKET' => 'exports',
      'AWS_ACCESS_KEY_ID' => 'example-access', 'AWS_SECRET_ACCESS_KEY' => 'example-secret')
    stub_request(:put, %r{https://account.r2.cloudflarestorage.com/exports/}).to_return(status: 307, headers: {'Location' => 'https://elsewhere.example/upload'})
    error = assert_raises(RuntimeError) { invoke_export }
    assert_match(/HTTP 307/, error.message)
    assert File.exist?(ENV['OUTPUT'])
    assert_not_requested :put, 'https://elsewhere.example/upload'
  end

  test 'S3 signature matches the AWS published PUT object example' do
    uploader = Corpus::Upload.new(endpoint: 'https://s3.amazonaws.com', bucket: 'examplebucket', region: 'us-east-1',
      access_key: 'AKIAIOSFODNN7EXAMPLE', secret_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY')
    headers = uploader.headers(URI('https://examplebucket.s3.amazonaws.com/test%24file.text'), Digest::SHA256.hexdigest('Welcome to Amazon S3.'), Time.utc(2013, 5, 24),
      'date' => 'Fri, 24 May 2013 00:00:00 GMT', 'x-amz-storage-class' => 'REDUCED_REDUNDANCY')
    assert headers.fetch('Authorization').end_with?('Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd')
  end

  test 'usage selection does not admit packages through shared repository popularity or quota fill' do
    npm = registry('npmjs.org', 'npm', packages_count: 100_000)
    go = registry('proxy.golang.org', 'go', packages_count: 100_000)
    used = package(npm, 'used-package', downloads: 5)
    shared = {'id' => 400, 'html_url' => 'https://github.com/example/popular', 'stargazers_count' => 100_000, 'forks_count' => 50_000}
    unrelated = [nil, 0].map.with_index { |downloads, i| package(npm, "unrelated-#{i}", downloads: downloads, repo_metadata: shared) }
    fallback = package(go, 'example.org/no-download-metric', downloads: nil, repo_metadata: shared)
    ENV.update('TARGET' => '20', 'CENSUS_LIMIT' => '0', 'HEAD_LIMIT' => '50')
    files = invoke_export
    records = json_rows(files, 'selection.ndjson.gz')
    assert_includes records.map { |r| r['package_id'] }, used
    assert_includes records.map { |r| r['package_id'] }, fallback
    records.select { |r| unrelated.include?(r['package_id']) }.each do |r|
      assert_equal 'background_outside99', r['reason']
    end
    report = JSON.parse(files.fetch('selection.json'))
    assert_includes report['package_usage_registries'], npm.id
    assert_not_includes report['package_usage_registries'], go.id
    quota = report.fetch('registry_quotas').fetch(npm.id.to_s)
    selected = records.select { |r| r['registry_id'] == npm.id }
    assert_operator selected.size, :<=, 1 + quota / 10
    assert_operator selected.count { |r| r['reason'] == 'background_outside99' }, :<=, quota / 10
    assert_not report['signals'].find { |s| s['registry_id'] == npm.id && s['signal'] == 'stargazers_count' }.fetch('selection_eligible')
  end
end
