require 'test_helper'
require 'rake'
require 'stringio'
require_relative '../../lib/package_corpus_export'
require_relative '../../lib/corpus_upload'

class CorpusRakeTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('exports:corpus')
    @dir = Dir.mktmpdir
    @env = ENV.to_h
    %w[UPLOAD SOURCE ASSIGNMENTS OUTPUT FILE S3_ENDPOINT S3_BUCKET S3_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN S3_PREFIX BATCH_SIZE].each { |key| ENV.delete(key) }
    ENV['OUTPUT'] = File.join(@dir, 'corpus.tar.gz')
    @created_packages = []
    @created_registries = []
  end

  teardown do
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
    assert_equal 3, statements.count { |sql| sql == 'SET TRANSACTION READ ONLY' }
    assert_equal 3, statements.count { |sql| sql.start_with?('EXPLAIN (FORMAT JSON)') }
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
    connection.stubs(:select_value).with(regexp_matches(/\AEXPLAIN/)).returns(JSON.generate([{'Plan' => {'Node Type' => 'Seq Scan', 'Total Cost' => 10000}}]))
    assert_match(/scan packages sequentially/, assert_raises(RuntimeError) { invoke_export }.message)
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
    uploader = CorpusUpload.new(endpoint: 'https://s3.amazonaws.com', bucket: 'examplebucket', region: 'us-east-1',
      access_key: 'AKIAIOSFODNN7EXAMPLE', secret_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY')
    headers = uploader.headers(URI('https://examplebucket.s3.amazonaws.com/test%24file.text'), Digest::SHA256.hexdigest('Welcome to Amazon S3.'), Time.utc(2013, 5, 24),
      'date' => 'Fri, 24 May 2013 00:00:00 GMT', 'x-amz-storage-class' => 'REDUCED_REDUNDANCY')
    assert headers.fetch('Authorization').end_with?('Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd')
  end
end
