require 'time'
require 'tempfile'
require 'zlib'
require_relative 'identity'

module Corpus
  class Projects
    def initialize(rows:, assignments:, as_of:)
      @rows = rows.to_h { |p| [p.fetch('package_id'), p] }
      @assignments = assignments
      @as_of = Time.iso8601(as_of)
      @identity = Identity.new
    end

    def strings(values)
      values.flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
    end

    def filters(values)
      result = strings(values).map(&:downcase).uniq.sort
      result.empty? ? ['unknown'] : result
    end

    def popularity(p)
      scores = %w[dependent_repos_count downloads].filter_map do |key|
        value = p.dig('rankings', key)
        next unless p.dig('signals', key).to_i.positive? && value.is_a?(Numeric) && value.finite? && value.between?(0, 100)
        [[-Math.log10([value, 0.0001].max) / 4, 0].max, 1].min
      end
      scores.empty? ? 0.0 : scores.sum.fdiv(scores.size)
    end

    def timestamp(value)
      Time.parse(value.to_s).utc.iso8601 unless value.to_s.empty?
    rescue ArgumentError
      nil
    end

    def build(members)
      first = members.first
      rows = members.map { |a| @rows.fetch(a.fetch('package_id')) }
      repositories = rows.select { |p| @identity.proof(p) && !@identity.blocked?(p) }.map { |p| p.fetch('repository') }
      names = strings(rows.map { |p| p['name'] } + repositories.map { |r| r['full_name'] })
      descriptions = strings(rows.map { |p| p['description'] } + repositories.map { |r| r['description'] })
      aliases = strings(rows.map { |p| [p['keywords'], p['keywords_array']] } + repositories.map { |r| [r['topics'], r['previous_names']] })
      roots = strings(rows.filter_map { |p| @identity.root(p.dig('repository', 'html_url')) if @identity.proof(p) })
      metadata = {
        'popularity' => rows.map { |p| popularity(p) }.max || 0.0,
        'dependents_max' => rows.map { |p| p.dig('signals', 'dependent_repos_count').to_i }.max || 0,
        'downloads_max' => rows.map { |p| p.dig('signals', 'downloads').to_i }.max || 0,
        'stars_max' => repositories.map { |r| r['stargazers_count'].to_i }.max || 0,
        'pushed_at' => repositories.filter_map { |r| timestamp(r['pushed_at']) }.max.to_s,
        'archived' => !repositories.empty? && repositories.all? { |r| r['archived'] == true }
      }
      pushed = timestamp(metadata['pushed_at'])
      metadata['activity'] = if metadata['archived']
        'archived'
      elsif pushed
        @as_of - Time.iso8601(pushed) <= 365 * 86400 ? 'active' : 'inactive'
      else
        'unknown'
      end
      categories = {
        'ecosystem' => filters(rows.map { |p| p['ecosystem'] }),
        'language' => filters(rows.map { |p| p['language'] } + repositories.map { |r| r['language'] }),
        'license' => filters(rows.map { |p| p['normalized_licenses'] } + repositories.map { |r| r['license'] }),
        'activity' => [metadata['activity']]
      }
      refs = rows.map do |p|
        {'snapshot_id' => p.fetch('package_id'), 'name' => p.fetch('name'), 'purl' => p['purl'], 'namespace' => p['namespace'],
          'registry' => p.dig('registry', 'name'), 'ecosystem' => p['ecosystem'], 'source_line' => p.fetch('source_line')}
      end
      display = repositories.filter_map { |r| r['description'] }.find { |d| !d.strip.empty? }
      display ||= rows.find { |p| p['name'] == first['display_name'] && !p['description'].to_s.strip.empty? }&.fetch('description')
      display ||= descriptions.first || 'No description available.'
      compact = {
        'id' => first.fetch('project_id'), 'name' => first.fetch('display_name'), 'reason' => first.fetch('reason'),
        'names' => names, 'descriptions' => descriptions, 'description' => display[0, 300], 'aliases' => aliases,
        'package_ids' => refs.map { |p| p['snapshot_id'] },
        'identifiers' => {'package_ids' => refs.map { |p| p['snapshot_id'] }, 'package_purls' => refs.map { |p| [p['snapshot_id'], p['purl']] }, 'repositories' => roots},
        'filters' => categories, 'ranking' => metadata.reject { |k, _| k == 'activity' },
        'public' => {'packages' => refs, 'verified_repositories' => roots.map { |r| 'https://' + r }, 'grouping_evidence' => first.fetch('reason')}
      }
      project = compact.slice('id', 'name', 'names', 'descriptions', 'aliases').merge(
        'packages' => rows.map { |p| {'id' => p['package_id'], 'name' => p['name'], 'purl' => p['purl'], 'origin' => {'registry' => p['registry'].slice('id', 'name', 'ecosystem', 'url'), 'namespace' => p['namespace'], 'source_line' => p['source_line']}} },
        'repositories' => roots, 'ecosystems' => categories['ecosystem'], 'languages' => categories['language'], 'licenses' => categories['license'], 'evidence' => first.fetch('reason')
      )
      metadata['latest'] = rows.to_h { |p| [p['package_id'].to_s, p.dig('activity', 'latest_release_number').to_s] }
      [compact, project, metadata]
    end

    def write(dir, package_sha)
      groups = @assignments.group_by { |a| a.fetch('project_id') }.sort
      Tempfile.create('project-metadata-', dir) do |metadata|
        File.open(File.join(dir, 'corpus.json'), 'w') do |corpus|
          corpus.write('{"as_of":' + JSON.generate(@as_of.iso8601) + ',"source":' + JSON.generate(path: 'packages.ndjson.gz', sha256: package_sha) + ',"projects":[')
          Zlib::GzipWriter.open(File.join(dir, 'projects.ndjson.gz')) do |gz|
            gz.mtime = 0
            groups.each_with_index do |(_, members), index|
              compact, project, detail = build(members.sort_by { |a| a['package_id'] })
              gz.puts(JSON.generate(compact))
              corpus.write(',') if index.positive?
              metadata.write(',') if index.positive?
              corpus.write(JSON.generate(project))
              metadata.write(JSON.generate(project['id']) + ':' + JSON.generate(detail))
            end
          end
          metadata.flush
          metadata.rewind
          corpus.write('],"metadata":{')
          IO.copy_stream(metadata, corpus)
          corpus.write('}}')
        end
      end
      groups.size
    end
  end
end
