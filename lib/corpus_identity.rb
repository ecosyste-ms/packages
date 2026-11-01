require 'digest'
require 'json'
require 'set'
require 'uri'

class CorpusIdentity
  COLLECTIONS = %w[github.com/definitelytyped/definitelytyped github.com/nixos/nixpkgs github.com/homebrew/homebrew-core github.com/conda-forge/staged-recipes github.com/spack/spack github.com/conan-io/conan-center-index github.com/docker-library/official-images github.com/flutter/packages github.com/dart-lang/tools github.com/csstools/postcss-plugins github.com/trezor/trezor-firmware github.com/flutter-team-archive/plugins github.com/oca/maintainer-tools github.com/apache/maven-apache-parent github.com/helm/charts github.com/openindiana/oi-userland github.com/stenciljs/component-starter github.com/apache/incubator-kie github.com/notofonts/noto-fonts github.com/pkgsrc/pkgsrc github.com/netbsd/pkgsrc].freeze
  COMPONENTS = {'alpine' => %w[main community testing], 'debian' => %w[main contrib non-free non-free-firmware], 'ubuntu' => %w[main universe multiverse restricted]}.freeze

  attr_reader :report

  def text(value)
    value.to_s.unicode_normalize(:nfkc).downcase.gsub(/\s+/, ' ').strip
  end

  def url(value)
    value = value.to_s.strip.sub(/\Agit\+/, '').sub(/\Agit@([^:]+):/, 'https://\1/')
    uri = URI.parse(value)
    return unless %w[http https git ssh].include?(uri.scheme) && uri.host && !uri.userinfo && [nil, 80, 443].include?(uri.port)
    "#{uri.host.downcase}#{uri.path.sub(/\.git\/?\z/i, '').sub(%r{/+\z}, '').downcase}"
  rescue URI::InvalidURIError
    nil
  end

  def root(value)
    normalized = url(value)
    return unless normalized
    host, *parts = normalized.split('/')
    return if parts.size < 2 || parts.any? { |s| s.empty? || %w[. ..].include?(s) }
    if %w[github.com bitbucket.org codeberg.org].include?(host)
      return if parts.size > 2 && !%w[tree blob src raw releases archive commit commits issues wiki].include?(parts[2])
      ([host] + parts.first(2)).join('/')
    elsif host.include?('gitlab') || host == 'salsa.debian.org'
      boundary = parts.index('-')
      ([host] + (boundary ? parts.first(boundary) : parts)).join('/')
    end
  end

  def homepage(value)
    uri = URI.parse(value.to_s.strip)
    return unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo
    host = uri.host.downcase.delete_prefix('www.')
    return if %w[github.com gitlab.com sourceforge.net].include?(host) && ['', '/'].include?(uri.path)
    host + ([80, 443].include?(uri.port) ? '' : ":#{uri.port}") + uri.path.sub(%r{/+\z}, '') + (uri.query ? "?#{uri.query}" : '')
  rescue URI::InvalidURIError
    nil
  end

  def blocked?(p)
    r = p['repository'] || {}
    known = [root(p['repository_url']), root(r['html_url'])].compact
    known.any? { |v| COLLECTIONS.include?(v) || v.start_with?('salsa.debian.org/rust-team/debcargo-conf') } ||
      r['description'].to_s.match?(/\b(?:collection of|curated|starter project|parent pom|packaging recipes)\b/i)
  end

  def variant?(p)
    p['description'].to_s.match?(/\b(?:fork(?:ed)?|unofficial|patched|sxmo)\b/i) || p['name'].to_s.start_with?('sxmo-')
  end

  def proof(p)
    r = p['repository'] || {}
    return unless r['id'].to_i.positive? && !blocked?(p) && !variant?(p)
    cached, declared = root(r['html_url']), root(p['repository_url'])
    return unless cached && declared
    return url(p['repository_url']) == cached ? 'root' : 'subpath' if cached == declared
    aliases = Array(r['previous_names']).filter_map { |name| "#{cached.split('/').first}/#{name.downcase}" if name.is_a?(String) }
    'alias' if aliases.include?(declared)
  end

  def namespace(p)
    COMPONENTS.fetch(p['ecosystem'].downcase, []).include?(p['namespace']) ? nil : p['namespace']
  end

  def lineage(p)
    family = p['ecosystem'].downcase
    r = p.fetch('registry')
    name = r.fetch('name').downcase
    if family == 'rubygems'
      mirrors = {'rubygems.org' => 'https://rubygems.org', 'gem.coop' => 'https://gem.coop'}
      return ['mirror', family, nil, p['name']] if p['namespace'].nil? && mirrors[name] == r['url'] && !p['name'].start_with?('@')
      return
    end
    valid = case family
    when 'nixpkgs'
      name.match?(/\Anixpkgs-(?:\d{2}\.\d{2}|unstable)\z/) && name == "nixpkgs-#{r['version']}" && r['url'] == "https://channels.nixos.org/nixos-#{r['version']}"
    when 'alpine', 'postmarketos'
      host = family == 'alpine' ? 'pkgs.alpinelinux.org' : 'pkgs.postmarketos.org'
      name.match?(/\A#{family}-(?:v\d+\.\d+|edge|master)\z/) && r['url'] == "https://#{host}/packages?branch=#{name.delete_prefix(family + '-')}"
    when 'debian', 'ubuntu'
      metadata = r['metadata'] || {}
      prefix = family == 'debian' ? 'https://packages.debian.org/' : 'https://launchpad.net/ubuntu/'
      name == "#{family}-#{r['version']}" && !metadata['codename'].to_s.empty? && r['url'] == prefix + metadata['codename']
    end
    return unless valid && r['ecosystem'].to_s.downcase == family && p['purl'].is_a?(String)
    path, query = p['purl'].split('?', 2)
    return if path.match?(/[@#]/) || p['purl'].include?('#')
    pairs = URI.decode_www_form(query.to_s)
    return unless pairs.map(&:first).uniq.size == pairs.size
    qualifiers = pairs.to_h
    type = family == 'nixpkgs' ? 'nix' : (%w[debian ubuntu].include?(family) ? 'deb' : 'apk')
    expected = "pkg:#{type}/#{family == 'nixpkgs' ? '' : family + '/'}#{p['name']}"
    return unless URI::DEFAULT_PARSER.unescape(path) == expected
    return if qualifiers['repository_url'] && qualifiers['repository_url'] != r['url']
    if family == 'nixpkgs'
      return unless qualifiers['channel'] == r['version']
      release = 'channel'
    elsif %w[debian ubuntu].include?(family)
      return unless qualifiers['arch'] == 'source' && qualifiers['distro'] == "#{family}-#{r['version']}"
      release = 'distro'
    else
      arch = p.dig('metadata', 'architecture')
      return if arch.to_s.empty? || qualifiers['arch'] != arch
    end
    stable = qualifiers.reject { |k, _| ['repository_url', release].include?(k) }.sort
    ['distribution', family, namespace(p), p['name'], stable]
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def people(p)
    keys = Array(p['maintainers']).flat_map do |m|
      values = ["registry:#{m['registry_id']}:#{m['id']}"]
      values << "email:#{m['email'].to_s.downcase.strip}" if m['email'].to_s.include?('@')
      profile = url(m['url'])
      values << "profile:#{profile}" if profile&.match?(%r{\A(?:github.com|gitlab.com|codeberg.org)/[^/]+\z})
      values
    end
    metadata = p['metadata'] || {}
    values = case p['ecosystem'].downcase
    when 'opam' then Array(metadata['maintainers'])
    when 'debian', 'ubuntu', 'freebsd' then [metadata['maintainer']]
    when 'bazel' then Array(metadata['maintainers']).filter_map { |v| v['email'] if v.is_a?(Hash) }
    else []
    end
    values.each { |value| value.to_s.scan(/[A-Z0-9.!#$%&'*+\/=\?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i).each { |email| keys << "email:#{email.downcase}" } }
    keys.reject { |key| key.match?(/(?:noreply|no-reply|lists\.|packages@|team@)/) }.uniq
  end

  def component?(p)
    return false if variant?(p)
    slug = root(p.dig('repository', 'html_url')).to_s.split('/').last.to_s
    tokens = ([slug] + slug.split(/[-_.]/)).select { |s| s.length >= 4 && !%w[python ruby perl rust java library libraries client server plugins packages fonts tools core].include?(s) }
    haystack = text([p['name'], p['description']].join(' ')).gsub(/[^a-z0-9]/, '')
    tokens.any? { |s| haystack.include?(s.gsub(/[^a-z0-9]/, '')) }
  end

  def assignments(rows)
    by_id = rows.to_h { |p| [p.fetch('package_id'), p] }
    raise 'Duplicate package ID' unless by_id.size == rows.size
    adjacency = Hash.new { |h, k| h[k] = Set.new }
    evidence = Hash.new { |h, k| h[k] = Set.new }
    keys = rows.to_h { |p| [p['package_id'], lineage(p)] }
    base_ids = rows.to_h do |p|
      verified = proof(p) == 'root' && root(p.dig('repository', 'html_url')).start_with?('github.com/')
      [p['package_id'], verified ? "repo:#{p.dig('repository', 'id')}" : "package:#{p['package_id']}"]
    end
    base_groups = rows.group_by { |p| base_ids.fetch(p['package_id']) }
    pure = base_groups.transform_values do |members|
      distinct = members.map { |p| keys[p['package_id']] }.uniq
      distinct.size == 1 ? distinct.first : nil
    end
    connect = lambda do |members, rule|
      ids = members.map { |p| p['package_id'] }.uniq.sort
      next if ids.size < 2
      ids.drop(1).each do |id|
        adjacency[ids.first] << id
        adjacency[id] << ids.first
        evidence[[ids.first, id]] << rule
      end
    end
    base_groups.each_value { |members| connect.call(members, 'repository_root') }
    rows.select { |p| keys[p['package_id']] && pure[base_ids[p['package_id']]] == keys[p['package_id']] }.group_by { |p| keys[p['package_id']] }.each do |key, members|
      next unless members.map { |p| p.dig('registry', 'id') }.uniq.size > 1
      connect.call(members, key.first == 'mirror' ? 'registry_mirror' : 'distribution_release')
    end
    supported = rows.select { |p| proof(p) }
    supported.group_by { |p| p.dig('repository', 'id') }.each_value do |bucket|
      bucket.group_by { |p| text(p['name']) }.each_value { |members| connect.call(members, 'repository_name') }
      components = bucket.select { |p| component?(p) }
      connect.call(components, 'repository_component')
      bucket.flat_map { |p| people(p).map { |person| [person, p] } }.group_by(&:first).each_value do |pairs|
        connect.call(pairs.map(&:last), 'repository_maintainer')
      end
    end
    safe = rows.reject { |p| blocked?(p) || variant?(p) }
    safe.select { |p| text(p['description']).length >= 24 && text(p['description']).split.size >= 4 }.group_by { |p| [text(p['name']), text(p['description'])] }.each_value do |bucket|
      bucket.select { |p| homepage(p['homepage']) }.group_by { |p| homepage(p['homepage']) }.each_value { |members| connect.call(members, 'name_description_homepage') }
      bucket.flat_map { |p| people(p).map { |person| [person, p] } }.group_by(&:first).each_value { |pairs| connect.call(pairs.map(&:last), 'name_description_maintainer') }
    end
    safe.select { |p| p['ecosystem'].downcase == 'alpine' && !p.dig('metadata', 'origin').to_s.empty? && homepage(p['homepage']) }.group_by { |p| [p.dig('metadata', 'origin'), homepage(p['homepage']), namespace(p), p.dig('metadata', 'architecture')] }.each do |key, members|
      connect.call(members, 'alpine_origin') if members.any? { |p| p['name'] == key.first }
    end
    safe.select { |p| %w[debian ubuntu].include?(p['ecosystem'].downcase) && p['purl'].to_s.include?('arch=source') && namespace(p).nil? && homepage(p['homepage']) && !p.dig('metadata', 'binary').to_s.empty? }.group_by do |p|
      [p['name'], homepage(p['homepage']), p.dig('metadata', 'binary').to_s.split(',').map(&:strip).sort]
    end.each_value { |members| connect.call(members, 'debian_ubuntu_source') }
    seen = Set.new
    groups = []
    rejected = Hash.new(0)
    by_id.keys.sort.each do |id|
      next if seen.include?(id)
      ids, pending = [], [id]
      until pending.empty?
        current = pending.pop
        next unless seen.add?(current)
        ids << current
        pending.concat(adjacency[current].to_a)
      end
      members = ids.map { |i| by_id.fetch(i) }
      repo_ids = members.reject { |p| blocked?(p) }.filter_map { |p| p.dig('repository', 'id') }.uniq
      attributes = members.select { |p| p['ecosystem'].downcase == 'nixpkgs' }.map { |p| [p['namespace'], p['name']] }.uniq
      existing_attributes = members.group_by { |p| base_ids[p['package_id']] }.values.map do |group|
        group.select { |p| p['ecosystem'].downcase == 'nixpkgs' }.map { |p| [p['namespace'], p['name']] }.uniq
      end
      attribute_conflict = attributes.size > 1 && existing_attributes.none? { |existing| (attributes - existing).empty? }
      if repo_ids.size > 1 || attribute_conflict
        rejected[repo_ids.size > 1 ? 'repository_conflict' : 'attribute_conflict'] += 1
        members.group_by do |p|
          base = base_ids[p['package_id']]
          pure[base] ? ['lineage', pure[base]] : ['base', base]
        end.each_value { |g| groups << g }
      else
        groups << members
      end
    end
    rules = Hash.new(0)
    assignments = groups.flat_map do |members|
      ids = members.map { |p| p['package_id'] }.sort
      distinct_keys = ids.map { |id| keys[id] }.uniq
      previous = ids.map { |id| base_ids[id] }.uniq.sort
      if previous.size == 1 && previous.first.start_with?('repo:')
        group_id, reason = previous.first, 'repository'
        name = root(members.first.dig('repository', 'html_url')).split('/').drop(1).join('/')
      elsif members.size == 1
        group_id, reason, name = "package:#{ids.first}", 'package', members.first['name']
      elsif distinct_keys.size == 1 && distinct_keys.first
        group_id = "lineage:#{Digest::SHA256.hexdigest(JSON.generate(distinct_keys.first))}"
        reason = distinct_keys.first.first == 'mirror' ? 'registry_mirror' : 'distribution_release'
        name = members.min_by { |p| p['package_id'] }['name']
      else
        group_id = "cross:#{Digest::SHA256.hexdigest(JSON.generate(previous))}"
        reason = 'repository'
        representative = members.select { |p| proof(p) == 'root' }.min_by { |p| p['package_id'] } || members.min_by { |p| p['package_id'] }
        name = proof(representative) ? root(representative.dig('repository', 'html_url')).split('/').drop(1).join('/') : representative['name']
      end
      rules[reason] += 1
      ids.map { |id| {'package_id' => id, 'previous_project_id' => "package:#{id}", 'project_id' => group_id, 'display_name' => name, 'reason' => reason} }
    end.sort_by { |p| p['package_id'] }
    @report = {packages: rows.size, projects: groups.size, reasons: rules, rejected_components: rejected, candidate_rules: evidence.values.flat_map(&:to_a).tally,
      limitations: 'Repository-root groups are provisional and exclude known collections and labelled variants. Homepage-only matches and inferred Nix names do not establish project identity.'}
    assignments
  end
end
