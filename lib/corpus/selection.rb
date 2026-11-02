require 'set'
require_relative 'database'

module Corpus
  class Selection
    METRICS = %w[downloads dependent_packages_count dependent_repos_count docker_downloads_count stargazers_count forks_count].freeze
    REGISTRY_SHIFT = 26
    BACKGROUND = 1 << 18
    CENSUS = 1 << 19
    ANCHOR_SHIFT = 20
    USAGE_MASK = 4.times.sum { |i| (7 << (3 * i)) | (1 << (ANCHOR_SHIFT + i)) }
    HEAD_MASK = 6.times.sum { |i| 1 << (3 * i) }
    OUTER_MASK = 6.times.sum { |i| 4 << (3 * i) }
    HASH_MASK = (1 << 64) - 1
    RETAINED = "(status IS NULL OR lower(status) <> 'removed')".freeze

    attr_reader :registries, :report, :selected

    def initialize(database:, target: 300_000, seed: 20261031, head_limit: 20_000, census_limit: 10_000, registry_floor: 500, registry_cap: 60_000)
      @database = database
      @target, @seed, @head_limit, @census_limit, @floor, @cap = [target, seed, head_limit, census_limit, registry_floor, registry_cap].map { |v| Integer(v) }
      raise ArgumentError, 'TARGET must be between 1 and 1000000' unless @target.between?(1, 1_000_000)
      raise ArgumentError, 'HEAD_LIMIT must be between 50 and 100000' unless @head_limit.between?(50, 100_000)
      raise ArgumentError, 'CENSUS_LIMIT must be between 0 and 10000' unless @census_limit.between?(0, 10_000)
      raise ArgumentError, 'Invalid registry floor or cap' unless @floor >= 0 && @cap.positive? && @floor <= @cap
      raise ArgumentError, 'SEED must be a nonnegative 32-bit integer' unless @seed.between?(0, 2**32 - 1)
      @pool = {}
      @usage_registries = []
    end

    def expression(metric)
      raise ArgumentError, 'Unknown signal' unless METRICS.include?(metric)
      %w[stargazers_count forks_count].include?(metric) ? "(repo_metadata->>'#{metric}')::integer" : metric
    end

    def run
      @registries = @database.read('SELECT * FROM registries ORDER BY id LIMIT 10001', limit: 10_000).to_h { |r| [r.fetch('id'), r] }
      coverage = []
      large = []
      @registries.each_value do |registry|
        id = registry.fetch('id')
        census = nil
        if registry.fetch('packages_count').to_i <= @census_limit
          columns = METRICS.map { |m| "#{expression(m)} AS #{m}" }.join(', ')
          rows = @database.read("SELECT id, #{columns} FROM packages WHERE registry_id = #{id} AND #{RETAINED} LIMIT #{@census_limit + 1}", limit: @census_limit + 1)
          census = rows if rows.size <= @census_limit
        end
        census&.each { |row| add(row['id'], id, CENSUS) }
        large << id unless census
        usage_only = false
        METRICS.each_with_index do |metric, index|
          if census
            pairs = census.filter_map { |p| [p['id'], p[metric]] if p[metric] && p[metric].positive? }
            truncated = false
          else
            expr = expression(metric)
            order = metric == 'docker_downloads_count' ? 'DESC' : 'DESC NULLS LAST'
            rows = @database.read("SELECT id, #{expr} AS value FROM packages WHERE registry_id = #{id} AND #{RETAINED} AND #{expr} > 0 ORDER BY #{expr} #{order} LIMIT #{@head_limit + 1}", limit: @head_limit + 1, cursor: true)
            truncated = rows.size > @head_limit
            pairs = rows.first(@head_limit).map { |p| [p['id'], p['value']] }
          end
          if metric == 'downloads' && !census && !pairs.empty?
            usage_only = true
            @usage_registries << id
          end
          coverage << classify(id, metric, index, pairs, truncated, eligible: !usage_only || index < 4)
          sleep 0.01
        end
      end
      unless large.empty?
        sample_limit = [@target, 100_000].min
        estimate = [@database.catalog.fetch('estimated_rows').to_i, sample_limit, 1].max
        percent = [100.0 * sample_limit / estimate, 100.0].min
        rows = @database.read("SELECT id, registry_id FROM packages TABLESAMPLE SYSTEM (#{percent}) REPEATABLE (#{@seed}) WHERE #{RETAINED} LIMIT #{sample_limit}", limit: sample_limit, sample: true)
        rows.each { |p| add(p['id'], p['registry_id'], BACKGROUND) if @registries.key?(p['registry_id']) }
      end
      groups = @pool.keys.group_by { |id| @pool.fetch(id) >> REGISTRY_SHIFT }
      quotas = allocate(groups.transform_values(&:size))
      @selected = {}
      groups.sort.each do |registry, ids|
        ids.sort_by! { |id| [stable_hash(id), id] }
        quota = quotas.fetch(registry)
        choices = {}
        round_robin(6.times.map { |i| ids.select { |id| @pool[id] & (1 << (ANCHOR_SHIFT + i)) != 0 } }, choices, (quota * 0.7).floor, 'signal_anchor')
        round_robin(6.times.map { |i| ids.select { |id| @pool[id] & (1 << (3 * i)) != 0 } }, choices, (quota * 0.7).floor, 'head90')
        round_robin(6.times.map { |i| ids.select { |id| @pool[id] & HEAD_MASK == 0 && @pool[id] & (4 << (3 * i)) != 0 } }, choices, (quota * 0.9).floor, 'outer90_to99')
        usage_only = @usage_registries.include?(registry)
        background_limit = usage_only ? [quota, choices.size + quota / 10].min : quota
        round_robin([ids.select { |id| @pool[id] & OUTER_MASK == 0 && @pool[id] & (BACKGROUND | CENSUS) != 0 }], choices, background_limit, 'background_outside99')
        fill = usage_only ? ids.select { |id| @pool[id] & USAGE_MASK != 0 } : ids
        round_robin([fill], choices, quota, 'registry_fill')
        choices.each { |id, reason| @selected[id] = {package_id: id, registry_id: registry, reason: reason, signal_membership: @pool[id] & ((1 << REGISTRY_SHIFT) - 1)} }
      end
      @report = {
        target: @target, selected: @selected.size, seed: @seed, registry_floor: @floor, registry_cap: @cap,
        head_limit: @head_limit, census_limit: @census_limit, candidates: @pool.size,
        allocation: 'Registry floors, then square-root population weights, subject to candidate capacity and registry caps.',
        mix: '70% signal anchors and 90% heads; 20% outer heads; 10% background where available, with deterministic registry fill.',
        package_usage_registries: @usage_registries,
        repository_signals: 'For non-census registries with observed positive downloads, stars and forks do not qualify packages. Background-only packages are capped at 10% of the registry quota; remaining slots require package-usage selection signals.',
        coverage_scope: 'Complete positive population for exhausted queries; observed indexed prefix otherwise. Prefix percentages are not registry-wide usage coverage.',
        ties: 'All cutoff ties within the observed pool are included. A bounded SQL prefix may cut a boundary tie; saved selection records freeze that choice.',
        background: 'Seeded SYSTEM page sample across the package population; small registries use a census. Sampling is approximate and changes when database storage changes.',
        registry_quotas: quotas, signals: coverage
      }
      @pool = nil
      @selected.keys.sort
    end

    def add(id, registry, flags)
      @pool[id] = @pool.fetch(id, registry << REGISTRY_SHIFT) | flags
    end

    def classify(registry, metric, index, pairs, truncated, eligible: true)
      pairs.sort_by! { |id, value| [-value, id] }
      total = pairs.sum(&:last)
      cutoffs = {}
      [90, 95, 99].each_with_index do |percent, level|
        sum = 0
        cutoff = pairs.find { |_, value| sum += value; sum * 100 >= total * percent }&.last
        cutoffs[percent] = cutoff
        pairs.each { |id, value| add(id, registry, 1 << (3 * index + level)) if eligible && cutoff && value >= cutoff }
      end
      pairs.first(50).each { |id, _| add(id, registry, 1 << (ANCHOR_SHIFT + index)) } if eligible
      {registry_id: registry, signal: metric, observed_packages: pairs.size, observed_total: total, truncated: truncated, cutoffs: cutoffs, selection_eligible: eligible}
    end

    def stable_hash(id)
      x = ((id ^ @seed) + 0x9e3779b97f4a7c15) & HASH_MASK
      x = ((x ^ (x >> 30)) * 0xbf58476d1ce4e5b9) & HASH_MASK
      x = ((x ^ (x >> 27)) * 0x94d049bb133111eb) & HASH_MASK
      x ^ (x >> 31)
    end

    def allocate(capacities)
      limits = capacities.transform_values { |n| [n, @cap].min }
      target = [@target, limits.values.sum].min
      floor = [@floor, target / [limits.size, 1].max].min
      result = limits.transform_values { |n| [n, floor].min }
      while result.values.sum < target
        remaining = target - result.values.sum
        eligible = result.keys.select { |id| result[id] < limits[id] }
        weights = eligible.to_h { |id| [id, Math.sqrt([@registries.fetch(id)['packages_count'].to_i, capacities[id], 1].max)] }
        additions = eligible.to_h { |id| [id, [(remaining * weights[id] / weights.values.sum).floor, limits[id] - result[id]].min] }
        eligible.sort_by { |id| [-weights[id], id] }.first(remaining).each { |id| additions[id] = 1 } if additions.values.sum.zero?
        additions.each { |id, n| result[id] += n }
      end
      result
    end

    def round_robin(lists, selected, limit, reason)
      positions = Array.new(lists.size, 0)
      loop do
        added = false
        lists.each_with_index do |list, i|
          break if selected.size >= limit
          positions[i] += 1 while positions[i] < list.size && selected.key?(list[positions[i]])
          next if positions[i] >= list.size
          selected[list[positions[i]]] = reason
          positions[i] += 1
          added = true
        end
        break if selected.size >= limit || !added
      end
    end
  end
end
