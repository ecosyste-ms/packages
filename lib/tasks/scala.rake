require 'csv'
require 'set'

SCALA_SUFFIX_RE = /(_sjs[0-9.]+|_native[0-9.]+)?_(2\.\d+|3)$/

def scala_strip_suffix(name)
  g, a = name.split(':', 2)
  return name if a.nil?
  "#{g}:#{a.sub(SCALA_SUFFIX_RE, '')}"
end

def scala_registry
  Registry.find_by_name!(ENV['REGISTRY'] || 'repo1.maven.org')
end

def scala_packages(registry)
  registry.packages.where(
    "split_part(packages.name, ':', 2) ~ ? OR packages.repo_metadata->>'language' = 'Scala'",
    '_(2\.1[0-3]|3)$'
  )
end

namespace :scala do
  desc "Top dependencies of published Scala packages (CSV to stdout). ENV: LIMIT (default 2000)"
  task export_dependencies: :environment do
    limit = (ENV['LIMIT'] || 2000).to_i
    reg = scala_registry
    scope = scala_packages(reg)

    $stderr.puts "collecting scala package ids..."
    pkg_repo = {}
    scope.in_batches(of: 5000) do |rel|
      rel.pluck(:id, :repository_url).each { |id, url| pkg_repo[id] = url }
    end
    $stderr.puts "  #{pkg_repo.size} scala packages"

    $stderr.puts "collecting latest version ids..."
    vid_pid = {}
    pkg_repo.keys.each_slice(5000) do |ids|
      Version.where(package_id: ids, latest: true).pluck(:id, :package_id).each { |vid, pid| vid_pid[vid] = pid }
    end
    $stderr.puts "  #{vid_pid.size} latest versions"

    $stderr.puts "aggregating dependencies..."
    agg = Hash.new { |h, k| h[k] = { pids: Set.new, repos: Set.new, raw: Set.new } }
    done = 0
    vid_pid.keys.each_slice(1000) do |vids|
      Dependency.where(version_id: vids).pluck(:version_id, :package_name).each do |vid, dep_name|
        next if dep_name.blank?
        pid = vid_pid[vid]
        entry = agg[scala_strip_suffix(dep_name)]
        entry[:pids] << pid
        entry[:repos] << pkg_repo[pid] if pkg_repo[pid].present?
        entry[:raw] << dep_name
      end
      done += vids.size
      $stderr.puts "  #{done}/#{vid_pid.size}" if (done % 20_000).zero?
    end
    $stderr.puts "  #{agg.size} distinct dependency names"

    ranked = agg.sort_by { |_, v| -v[:repos].size }.first(limit)

    $stderr.puts "looking up dependency metadata..."
    raw_names = ranked.flat_map { |_, v| v[:raw].to_a }.uniq
    meta = {}
    raw_names.each_slice(1000) do |names|
      reg.packages.where(name: names).each do |p|
        logical = scala_strip_suffix(p.name)
        cur = meta[logical]
        meta[logical] = p if cur.nil? || (p.dependent_packages_count || 0) > (cur.dependent_packages_count || 0)
      end
    end

    puts CSV.generate_line(%w[
      logical_name scala_dependent_projects scala_dependent_packages
      language repository_url homepage latest_release_published_at
      total_dependent_packages status stars last_repo_push archived example_purl
    ])
    ranked.each do |logical, v|
      p = meta[logical]
      rm = p&.repo_metadata || {}
      puts CSV.generate_line([
        logical,
        v[:repos].size,
        v[:pids].size,
        rm['language'],
        p&.repository_url,
        p&.homepage,
        p&.latest_release_published_at&.iso8601,
        p&.dependent_packages_count,
        p&.status,
        rm['stargazers_count'],
        rm['pushed_at'],
        rm['archived'],
        p&.purl
      ])
    end
    $stderr.puts "done: #{ranked.size} rows"
  end

  desc "Scala source projects on Maven Central grouped by repository (CSV to stdout)"
  task export_projects: :environment do
    reg = scala_registry
    scope = scala_packages(reg).where.not(repository_url: [nil, ''])

    $stderr.puts "grouping by repository_url..."
    projects = Hash.new { |h, k| h[k] = { artifacts: 0, group_ids: Set.new, dep_pkgs: 0, dep_repos: 0, latest: nil, rm: nil, example: nil } }
    scope.in_batches(of: 5000) do |rel|
      rel.each do |p|
        e = projects[p.repository_url]
        e[:artifacts] += 1
        e[:group_ids] << p.name.split(':', 2).first
        e[:dep_pkgs] += p.dependent_packages_count.to_i
        e[:dep_repos] += p.dependent_repos_count.to_i
        e[:latest] = [e[:latest], p.latest_release_published_at].compact.max
        e[:rm] ||= p.repo_metadata if p.repo_metadata.present?
        e[:example] ||= p.name
      end
    end
    $stderr.puts "  #{projects.size} projects"

    puts CSV.generate_line(%w[
      repository_url group_ids artifact_count total_dependent_packages
      total_dependent_repos latest_release_published_at language stars
      forks last_repo_push archived example_artifact
    ])
    projects.sort_by { |_, v| -v[:dep_pkgs] }.each do |repo, v|
      rm = v[:rm] || {}
      puts CSV.generate_line([
        repo,
        v[:group_ids].to_a.sort.join(' '),
        v[:artifacts],
        v[:dep_pkgs],
        v[:dep_repos],
        v[:latest]&.iso8601,
        rm['language'],
        rm['stargazers_count'],
        rm['forks_count'],
        rm['pushed_at'],
        rm['archived'],
        v[:example]
      ])
    end
    $stderr.puts "done: #{projects.size} rows"
  end
end
