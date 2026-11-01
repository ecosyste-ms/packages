require 'digest'
require 'fileutils'
require 'json'
require 'rubygems/package'
require 'set'
require 'tempfile'
require 'tmpdir'
require 'zlib'

class PackageCorpusExport
  REASONS = %w[repository package distribution_release registry_mirror].freeze
  FIELDS = %w[name ecosystem namespace description homepage repository_url licenses normalized_licenses language status critical keywords keywords_array metadata rankings].freeze
  SIGNALS = %w[downloads downloads_period dependent_packages_count dependent_repos_count docker_downloads_count docker_dependents_count maintainers_count].freeze
  ACTIVITY = %w[latest_release_number latest_published_release_number latest_release_published_at first_release_published_at last_synced_at created_at updated_at repo_metadata_updated_at versions_count versions_updated_at].freeze

  def initialize(manifest:, output:, source: nil, batch_size: 250)
    @manifest_path = File.expand_path(manifest)
    @input = JSON.parse(File.read(@manifest_path))
    @output = File.expand_path(output)
    @source = source && File.expand_path(source)
    @batch_size = Integer(batch_size)
    raise ArgumentError, 'BATCH_SIZE must be between 1 and 1000' unless @batch_size.between?(1, 1000)
    raise ArgumentError, 'Output already exists' if File.exist?(@output)
  end

  def run
    assignments = load_assignments
    removed = @input.fetch('known_newly_removed_package_ids', []).to_set
    started = Time.now.utc.iso8601
    FileUtils.mkdir_p(File.dirname(@output))
    Dir.mktmpdir('package-export-', File.dirname(@output)) do |dir|
      counts = Hash.new(0)
      missing = Hash.new(0)
      groups = {}
      retained = 0
      seen = Set.new
      excluded = []
      gzip(File.join(dir, 'packages.ndjson.gz')) do |packages|
        gzip(File.join(dir, 'assignments.ndjson.gz')) do |members|
          each_package(assignments.keys.sort) do |record|
            id = record.fetch('package_id')
            assignment = assignments.fetch(id)
            raise "Duplicate source package #{id}" unless seen.add?(id)
            if record['status'].to_s.downcase == 'removed' || removed.include?(id)
              excluded << {'package_id' => id, 'reason' => 'removed'}
              next
            end
            packages.puts(JSON.generate(record))
            members.puts(JSON.generate(assignment))
            retained += 1
            counts[[record.dig('registry', 'id'), record.dig('registry', 'name'), record['ecosystem']]] += 1
            %w[purl description homepage repository_url].each { |field| missing[field] += 1 if record[field].nil? }
            signals = record.fetch('signals')
            %w[downloads dependent_packages_count dependent_repos_count docker_downloads_count stargazers_count forks_count].each do |field|
              missing["signals.#{field}"] += 1 if signals[field].nil?
            end
            group = (groups[assignment.fetch('project_id')] ||= {
              'id' => assignment.fetch('project_id'), 'name' => assignment.fetch('display_name'),
              'reason' => assignment.fetch('reason'), 'package_ids' => []
            })
            group['package_ids'] << id
          end
        end
      end
      absent = assignments.keys - seen.to_a
      raise "Selected packages missing from source (#{absent.size}): #{absent.first(10).join(', ')}" unless absent.empty?
      raise 'No retained packages' if retained.zero?
      gzip(File.join(dir, 'projects.ndjson.gz')) { |gz| groups.sort.each { |_, group| gz.puts(JSON.generate(group)) } }
      File.write(File.join(dir, 'excluded.json'), JSON.pretty_generate(excluded))
      files = Dir.children(dir).sort.to_h { |name| [name, file_info(File.join(dir, name))] }
      assignment_manifest = @input.slice('source_corpus_sha256', 'as_of').merge(
        'source_package_path' => 'packages.ndjson.gz', 'source_package_sha256' => files.fetch('packages.ndjson.gz').fetch('sha256'),
        'assignments_file' => 'assignments.ndjson.gz', 'assignments_sha256' => files.fetch('assignments.ndjson.gz').fetch('sha256'),
        'packages' => retained, 'projects' => groups.size, 'reason_values' => REASONS, 'experimental' => true,
        'description' => 'Supplied project assignments, with removed packages excluded. Grouping and selection are not recalculated.'
      )
      File.write(File.join(dir, 'assignment-manifest.json'), JSON.pretty_generate(assignment_manifest))
      files['assignment-manifest.json'] = file_info(File.join(dir, 'assignment-manifest.json'))
      manifest = {
        'experimental' => true, 'records' => retained, 'projects' => groups.size,
        'sha256' => files.fetch('packages.ndjson.gz').fetch('sha256'),
        'extraction_started_at' => started, 'extraction_finished_at' => Time.now.utc.iso8601,
        'source' => @source ? 'snapshot' : 'database', 'source_snapshot_sha256' => @source && Digest::SHA256.file(@source).hexdigest,
        'parent_assignment_manifest_sha256' => Digest::SHA256.file(@manifest_path).hexdigest,
        'selection' => 'All package IDs in the supplied assignments, excluding removed records.',
        'grouping' => 'Supplied assignments preserved; refreshed metadata does not revalidate identity.',
        'consistency' => @source ? 'Checksum-verified source snapshot.' : 'Read-only batches; records can change between batches.',
        'registries' => counts.sort_by { |key, _| key.map(&:to_s) }.map { |(id, name, ecosystem), count| {id: id, name: name, ecosystem: ecosystem, packages: count} },
        'null_counts' => missing, 'excluded_packages' => excluded.size, 'files' => files
      }
      if @source && manifest.fetch('source_snapshot_sha256') != @input.fetch('source_package_sha256')
        raise 'Source changed during export'
      end
      manifest['database'] = @database if @database
      File.write(File.join(dir, 'manifest.json'), JSON.pretty_generate(manifest))
      archive(dir)
      manifest.merge('archive' => @output, 'archive_sha256' => Digest::SHA256.file(@output).hexdigest)
    end
  end

  def load_assignments
    path = File.expand_path(@input.fetch('assignments_file'), File.dirname(@manifest_path))
    raise 'Assignment checksum differs' unless Digest::SHA256.file(path).hexdigest == @input.fetch('assignments_sha256')
    assignments = {}
    groups = {}
    Zlib::GzipReader.open(path) do |gz|
      gz.each_line do |line|
        row = JSON.parse(line)
        id = row.fetch('package_id')
        raise 'Invalid package ID' unless id.is_a?(Integer) && id.positive?
        raise "Duplicate assignment #{id}" if assignments.key?(id)
        %w[project_id display_name previous_project_id].each { |key| raise "Missing #{key}" if row[key].to_s.strip.empty? }
        raise 'Unknown grouping reason' unless REASONS.include?(row['reason'])
        identity = row.values_at('display_name', 'reason')
        prior = groups[row['project_id']]
        raise 'Conflicting group metadata' if prior && prior != identity
        groups[row['project_id']] = identity
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
      Zlib::GzipReader.open(@source) do |gz|
        gz.each_line do |line|
          record = JSON.parse(line)
          yield record if selected.include?(record.fetch('package_id'))
        end
      end
    else
      ids.each_slice(@batch_size) do |batch|
        database_batch(batch).each { |record| yield record }
        sleep 0.1
      end
    end
  end

  def database_batch(ids)
    Package.connection_pool.with_connection do |connection|
      connection.transaction do
        connection.execute('SET TRANSACTION READ ONLY')
        connection.execute("SET LOCAL statement_timeout = '5s'")
        connection.execute("SET LOCAL lock_timeout = '500ms'")
        connection.execute("SET LOCAL idle_in_transaction_session_timeout = '15s'")
        @database ||= {
          'table' => connection.select_one("SELECT reltuples::bigint AS estimated_rows, pg_total_relation_size(oid) AS total_bytes FROM pg_class WHERE oid = 'packages'::regclass"),
          'indexes' => connection.select_values("SELECT indexdef FROM pg_indexes WHERE schemaname = current_schema() AND tablename = 'packages'"),
          'batch_size' => @batch_size, 'statement_timeout_ms' => 5000, 'lock_timeout_ms' => 500
        }
        relation = Package.where(id: ids).order(:id).select(:id, :registry_id, :repo_metadata, *FIELDS, *SIGNALS, *ACTIVITY)
        plan = JSON.parse(connection.select_value("EXPLAIN (FORMAT JSON) #{relation.to_sql}"))
        # Tiny tables may legitimately use a sequential scan during local runs.
        if plan.to_json.include?('Seq Scan') && plan.first.fetch('Plan').fetch('Total Cost') > 100
          raise 'Export would scan packages sequentially'
        end
        rows = relation.to_a
        registries = Registry.where(id: rows.map(&:registry_id).uniq).index_by(&:id)
        rows.map do |package|
          package.registry = registries.fetch(package.registry_id)
          repository = package.repo_metadata.is_a?(Hash) ? package.repo_metadata : nil
          package.attributes.slice(*FIELDS).merge(
            'package_id' => package.id, 'purl' => package.purl,
            'registry' => package.registry.attributes.slice('id', 'name', 'url', 'ecosystem'),
            'repository' => repository,
            'signals' => package.attributes.slice(*SIGNALS).merge('stargazers_count' => repository&.[]('stargazers_count'), 'forks_count' => repository&.[]('forks_count')),
            'activity' => package.attributes.slice(*ACTIVITY),
            'provenance' => {'source_database' => Rails.env, 'retrieved_at' => Time.now.utc.iso8601, 'source_registry_id' => package.registry_id}
          )
        end
      end
    end
  end

  def gzip(path)
    Zlib::GzipWriter.open(path) do |gz|
      gz.mtime = 0
      yield gz
    end
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
