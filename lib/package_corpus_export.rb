require 'digest'
require 'fileutils'
require 'json'
require 'rubygems/package'
require 'set'
require 'tempfile'
require 'tmpdir'
require 'zlib'
require_relative 'corpus_selection'
require_relative 'corpus_projects'

class PackageCorpusExport
  REASONS = %w[repository package distribution_release registry_mirror].freeze
  FIELDS = %w[name ecosystem namespace description homepage repository_url licenses normalized_licenses language status critical keywords keywords_array metadata rankings].freeze
  SIGNALS = %w[downloads downloads_period dependent_packages_count dependent_repos_count docker_downloads_count docker_dependents_count maintainers_count].freeze
  ACTIVITY = %w[latest_release_number latest_published_release_number latest_release_published_at first_release_published_at last_synced_at created_at updated_at repo_metadata_updated_at versions_count versions_updated_at].freeze

  def initialize(output:, manifest: nil, source: nil, batch_size: 250, **selection)
    @manifest_path = manifest && File.expand_path(manifest)
    @input = @manifest_path ? JSON.parse(File.read(@manifest_path)) : {}
    @output = File.expand_path(output)
    @source = source && File.expand_path(source)
    @batch_size = Integer(batch_size)
    @selection_options = selection
    raise ArgumentError, 'SOURCE replay requires ASSIGNMENTS; database exports need neither' if @source && !@manifest_path
    raise ArgumentError, 'BATCH_SIZE must be between 1 and 1000' unless @batch_size.between?(1, 1000)
    raise ArgumentError, 'Output already exists' if File.exist?(@output)
  end

  def run
    started = Time.now.utc.iso8601
    if @manifest_path
      assignments = load_assignments
      ids = assignments.keys.sort
    else
      @database = CorpusDatabase.new
      @selector = CorpusSelection.new(database: @database, **@selection_options)
      ids = @selector.run
      @registries = @selector.registries.transform_values { |r| Registry.instantiate(r) }
      assignments = nil
    end
    raise 'No packages selected' if ids.empty?
    removed = @input.fetch('known_newly_removed_package_ids', []).to_set
    FileUtils.mkdir_p(File.dirname(@output))
    Dir.mktmpdir('package-export-', File.dirname(@output)) do |dir|
      rows, excluded, seen = [], [], Set.new
      counts, missing = Hash.new(0), Hash.new(0)
      gzip(File.join(dir, 'packages.ndjson.gz')) do |packages|
        each_package(ids) do |record|
          id = record.fetch('package_id')
          raise "Duplicate source package #{id}" unless seen.add?(id)
          if record['status'].to_s.downcase == 'removed' || removed.include?(id)
            excluded << {'package_id' => id, 'reason' => 'removed'}
            next
          end
          record['provenance']['selection'] = @selector.selected.fetch(id) if @selector
          packages.puts(JSON.generate(record))
          rows << projection(record).merge('source_line' => rows.size + 1)
          counts[[record.dig('registry', 'id'), record.dig('registry', 'name'), record['ecosystem']]] += 1
          %w[purl description homepage repository_url].each { |field| missing[field] += 1 if record[field].nil? }
          CorpusSelection::METRICS.each { |field| missing["signals.#{field}"] += 1 if record.dig('signals', field).nil? }
        end
      end
      absent = ids - seen.to_a
      raise "Selected packages missing from source (#{absent.size}): #{absent.first(10).join(', ')}" unless absent.empty?
      raise 'No retained packages' if rows.empty?
      if assignments
        retained = rows.map { |r| r['package_id'] }.to_set
        assignments = assignments.values.select { |a| retained.include?(a['package_id']) }.sort_by { |a| a['package_id'] }
      else
        identity = CorpusIdentity.new
        assignments = identity.assignments(rows)
        File.write(File.join(dir, 'identity.json'), JSON.pretty_generate(identity.report))
        File.write(File.join(dir, 'selection.json'), JSON.pretty_generate(@selector.report))
        gzip(File.join(dir, 'selection.ndjson.gz')) { |gz| @selector.selected.sort.each { |_, r| gz.puts(JSON.generate(r)) } }
      end
      gzip(File.join(dir, 'assignments.ndjson.gz')) { |gz| assignments.each { |a| gz.puts(JSON.generate(a)) } }
      package_sha = Digest::SHA256.file(File.join(dir, 'packages.ndjson.gz')).hexdigest
      as_of = @input.fetch('as_of', started)
      groups = CorpusProjects.new(rows: rows, assignments: assignments, as_of: as_of).write(dir, package_sha)
      File.write(File.join(dir, 'excluded.json'), JSON.pretty_generate(excluded))
      assignment_manifest = @input.slice('source_corpus_sha256').merge(
        'as_of' => as_of, 'source_package_path' => 'packages.ndjson.gz', 'source_package_sha256' => package_sha,
        'assignments_file' => 'assignments.ndjson.gz', 'assignments_sha256' => Digest::SHA256.file(File.join(dir, 'assignments.ndjson.gz')).hexdigest,
        'packages' => rows.size, 'projects' => groups, 'reason_values' => REASONS, 'experimental' => true,
        'description' => @manifest_path ? 'Supplied assignments with removed packages excluded.' : 'Generated from stored package metadata. corpus.json is self-contained; no prior corpus is required.'
      )
      File.write(File.join(dir, 'assignment-manifest.json'), JSON.pretty_generate(assignment_manifest))
      files = Dir.children(dir).sort.to_h { |name| [name, file_info(File.join(dir, name))] }
      manifest = {
        'experimental' => true, 'records' => rows.size, 'projects' => groups, 'sha256' => package_sha,
        'extraction_started_at' => started, 'extraction_finished_at' => Time.now.utc.iso8601, 'as_of' => as_of,
        'source' => @source ? 'snapshot' : 'database', 'source_snapshot_sha256' => @source && Digest::SHA256.file(@source).hexdigest,
        'parent_assignment_manifest_sha256' => @manifest_path && Digest::SHA256.file(@manifest_path).hexdigest,
        'selection' => @selector ? @selector.report : 'Supplied package selection.',
        'grouping' => identity ? identity.report : 'Supplied assignments preserved.',
        'consistency' => @source ? 'Checksum-verified source snapshot.' : 'Read-only batches; records can change between batches.',
        'registries' => counts.sort_by { |key, _| key.map(&:to_s) }.map { |(id, name, ecosystem), count| {id: id, name: name, ecosystem: ecosystem, packages: count} },
        'null_counts' => missing, 'excluded_packages' => excluded.size, 'files' => files,
        'project_records_file' => 'projects.ndjson.gz', 'corpus_file' => 'corpus.json', 'package_records_file' => 'packages.ndjson.gz'
      }
      raise 'Source changed during export' if @source && manifest['source_snapshot_sha256'] != @input.fetch('source_package_sha256')
      manifest['database'] = @database.catalog.merge('queries' => @database.queries, 'batch_size' => @batch_size, 'statement_timeout_ms' => 5000, 'lock_timeout_ms' => 500) if @database
      File.write(File.join(dir, 'manifest.json'), JSON.pretty_generate(manifest))
      archive(dir)
      manifest.merge('archive' => @output, 'archive_sha256' => Digest::SHA256.file(@output).hexdigest)
    end
  end

  def projection(record)
    result = record.dup
    metadata = record['metadata'].is_a?(Hash) ? record['metadata'] : {}
    result['metadata'] = metadata.slice('origin', 'binary', 'architecture', 'maintainers', 'maintainer', 'urls', 'source_url')
    result['repository'] = (record['repository'] || {}).slice('id', 'html_url', 'full_name', 'description', 'language', 'license', 'topics', 'previous_names', 'pushed_at', 'archived', 'fork', 'stargazers_count', 'last_synced_at')
    result.delete('provenance')
    result
  end

  def load_assignments
    path = File.expand_path(@input.fetch('assignments_file'), File.dirname(@manifest_path))
    raise 'Assignment checksum differs' unless Digest::SHA256.file(path).hexdigest == @input.fetch('assignments_sha256')
    assignments, groups = {}, {}
    Zlib::GzipReader.open(path) do |gz|
      gz.each_line do |line|
        row = JSON.parse(line)
        id = row.fetch('package_id')
        raise 'Invalid package ID' unless id.is_a?(Integer) && id.positive?
        raise "Duplicate assignment #{id}" if assignments.key?(id)
        %w[project_id display_name previous_project_id].each { |key| raise "Missing #{key}" if row[key].to_s.strip.empty? }
        raise 'Unknown grouping reason' unless REASONS.include?(row['reason'])
        metadata = row.values_at('display_name', 'reason')
        raise 'Conflicting group metadata' if groups[row['project_id']] && groups[row['project_id']] != metadata
        groups[row['project_id']] = metadata
        assignments[id] = row
      end
    end
    raise 'Assignment counts differ' unless assignments.size == @input.fetch('packages') && groups.size == @input.fetch('projects')
    assignments
  end

  def each_package(ids)
    if @source
      raise 'Source checksum differs' unless Digest::SHA256.file(@source).hexdigest == @input.fetch('source_package_sha256')
      selected = ids.to_set
      Zlib::GzipReader.open(@source) { |gz| gz.each_line { |line| record = JSON.parse(line); yield record if selected.include?(record.fetch('package_id')) } }
    else
      ids.each_slice(@batch_size) do |batch|
        database_batch(batch).each { |record| yield record }
        sleep 0.1
      end
    end
  end

  def database_batch(ids)
    @database ||= CorpusDatabase.new
    relation = Package.where(id: ids).order(:id).select(:id, :registry_id, :repo_metadata, *FIELDS, *SIGNALS, *ACTIVITY)
    packages = @database.read(relation.to_sql, limit: ids.size).map { |row| Package.instantiate(row) }
    @registries ||= {}
    missing = packages.map(&:registry_id).uniq - @registries.keys
    unless missing.empty?
      @database.read(Registry.where(id: missing).to_sql, limit: missing.size).each { |r| @registries[r['id']] = Registry.instantiate(r) }
    end
    people = {}
    with_people = packages.select { |p| p.maintainers_count.to_i.positive? }.map(&:id)
    unless with_people.empty?
      sql = "SELECT ms.package_id, m.id, m.registry_id, m.email, m.url, m.login FROM maintainerships ms JOIN maintainers m ON m.id = ms.maintainer_id WHERE ms.package_id IN (#{with_people.join(',')}) LIMIT 50001"
      people = @database.read(sql, limit: 50_000).group_by { |r| r.fetch('package_id') }
    end
    packages.map do |package|
      package.registry = @registries.fetch(package.registry_id)
      repository = package.repo_metadata.is_a?(Hash) ? package.repo_metadata : nil
      package.attributes.slice(*FIELDS).merge(
        'package_id' => package.id, 'purl' => package.purl,
        'registry' => package.registry.attributes.slice('id', 'name', 'url', 'ecosystem', 'version', 'metadata'),
        'repository' => repository, 'maintainers' => people.fetch(package.id, []),
        'signals' => package.attributes.slice(*SIGNALS).merge('stargazers_count' => repository&.[]('stargazers_count'), 'forks_count' => repository&.[]('forks_count')),
        'activity' => package.attributes.slice(*ACTIVITY),
        'provenance' => {'source_database' => Rails.env, 'retrieved_at' => Time.now.utc.iso8601, 'source_registry_id' => package.registry_id}
      )
    end
  end

  def gzip(path)
    Zlib::GzipWriter.open(path) { |gz| gz.mtime = 0; yield gz }
  end

  def file_info(path)
    {'bytes' => File.size(path), 'sha256' => Digest::SHA256.file(path).hexdigest}
  end

  def archive(dir)
    Tempfile.create(['package-export-', '.tar.gz'], File.dirname(@output)) do |file|
      gzip(file.path) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          Dir.children(dir).sort.each do |name|
            path = File.join(dir, name)
            tar.add_file_simple(name, 0o644, File.size(path)) { |entry| File.open(path, 'rb') { |input| IO.copy_stream(input, entry) } }
          end
        end
      end
      File.link(file.path, @output)
    end
  end
end
