module Cleanup
  class Base
    STATE_KEY = 'registry_cleanup'.freeze
    BATCH_SIZE = 100
    MAX_FAILURES = 100

    def initialize(registry, run: 'all', dry_run: true, limit: 100, max_seconds: 600, pause: 1,
      from_id: 0, to_id: nil, name: nil, output: $stdout)
      raise ArgumentError, 'Invalid run name' unless run.match?(/\A[a-zA-Z0-9_-]{1,64}\z/)
      raise ArgumentError, 'LIMIT must be positive' unless limit.positive?
      raise ArgumentError, 'MAX_SECONDS must be positive and finite' unless max_seconds.finite? && max_seconds.positive?
      raise ArgumentError, 'PAUSE must be nonnegative and finite' unless pause.finite? && pause >= 0
      raise ArgumentError, 'Invalid ID range' unless from_id >= 0 && (to_id.nil? || to_id >= from_id)
      raise ArgumentError, 'Invalid package NAME' if name && name.blank?
      @registry = registry
      @run = run
      @dry_run = dry_run
      @limit = limit
      @max_seconds = max_seconds
      @pause = [pause, registry.rate_limit.to_f.positive? ? 1.0 / registry.rate_limit : 0].max
      @scope = {'from_id' => from_id, 'to_id' => to_id, 'name' => name.presence&.downcase}
      @output = output
    end

    def run
      Registry.connection_pool.with_connection do |connection|
        key = connection.quote("registry_cleanup:#{@registry.id}")
        acquired = connection.select_value("SELECT pg_try_advisory_lock(hashtextextended(#{key}, 0))")
        raise 'Another cleanup is running for this registry' unless acquired
        begin
          run_batches
        ensure
          connection.execute("SELECT pg_advisory_unlock(hashtextextended(#{key}, 0))")
        end
      end
    end

    def run_batches
      @registry.reload
      validate_run
      @state = @registry.metadata.to_h.dig(self.class::STATE_KEY, @run)&.deep_dup
      raise ArgumentError, 'Run scope differs from its checkpoint; choose another RUN' if @state && @state.fetch('scope') != @scope
      @state ||= {'scope' => @scope, 'started_at' => Time.current.iso8601,
        'max_id' => [@registry.packages.maximum(:id).to_i, @scope['to_id']].compact.min,
        'after_name' => nil, 'processed' => 0, 'failures' => {}}.merge(initial_counters)
      @attempted = 0
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      emit(event: 'start', scope: @scope, checkpoint: @state)

      @state.fetch('failures').values.each do |failure|
        break if budget_exhausted?
        process(failure.fetch('id'), failure.fetch('name'), retrying: true)
      end
      after_name = @state['after_name']
      loop do
        break if budget_exhausted? || @state.fetch('failures').size >= MAX_FAILURES
        batch = remaining(after_name).limit([BATCH_SIZE, @limit - @attempted].min).pluck(:id, :name)
        break if batch.empty?
        batch.each do |id, name|
          break if budget_exhausted? || @state.fetch('failures').size >= MAX_FAILURES
          process(id, name)
          after_name = name
        end
      end
      complete = !remaining(after_name).exists? && @state.fetch('failures').empty?
      summary = {event: 'summary', attempted: @attempted, processed: @state.fetch('processed'),
        after_name: after_name, max_id: @state.fetch('max_id'), failures: @state.fetch('failures'),
        complete: complete}.merge(@state.slice(*initial_counters.keys).symbolize_keys)
      emit(**summary)
      summary
    end

    def remaining(after_name)
      relation = @registry.packages.where(id: @scope.fetch('from_id')..@state.fetch('max_id'))
      relation = relation.where('lower(name) = ?', @scope['name']) if @scope['name']
      relation = relation.where('name > ?', after_name) if after_name
      relation.order(:name)
    end

    def budget_exhausted?
      @attempted >= @limit || Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started >= @max_seconds
    end

    def process(id, name, retrying: false)
      @attempted += 1
      result = @dry_run ? preview(id, name, retrying: retrying) : apply_package(id, name, retrying: retrying)
      emit(**result)
    ensure
      if !@dry_run && @pause.positive? && !budget_exhausted?
        remaining_seconds = @max_seconds - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started)
        sleep [@pause, remaining_seconds].min if remaining_seconds.positive?
      end
    end

    def preview(id, name, retrying:)
      package = @registry.packages.find_by(id: id)
      {event: 'preview', id: id, name: name, status: package&.status,
        stored_versions: package&.versions_count, retrying: retrying}.merge(preview_package(package))
    end

    def apply_package(id, name, retrying:)
      registry = Registry.find(@registry.id)
      package = registry.packages.find_by(id: id)
      before = package&.status
      prepared = prepare_package(registry, package) if package
      next_state = nil
      result = Registry.transaction do
        counters = initial_counters.symbolize_keys
        if package
          counters = repair_package(registry, package, prepared)
          package = registry.packages.find(id)
        end
        next_state = checkpoint(registry, id, name, retrying: retrying, counters: counters)
        {event: package ? 'applied' : 'missing', id: id, name: name, status_before: before,
          status_after: package&.status, versions: package&.versions_count}.merge(counters)
      end
      @state = next_state
      result
    rescue StandardError => error
      @state = checkpoint(Registry.find(@registry.id), id, name, retrying: retrying, error: error)
      {event: 'failed', id: id, name: name, error: "#{error.class}: #{error.message}".truncate(500)}
    end

    def validate_run
    end

    def initial_counters
      {}
    end

    def preview_package(_package)
      {}
    end

    def prepare_package(_registry, _package)
    end

    def repair_package(_registry, _package, _prepared)
      raise NotImplementedError, 'Implement the ecosystem repair in a Cleanup::Base subclass'
    end

    def checkpoint(registry, id, name, retrying:, counters: {}, error: nil)
      state = @state.deep_dup
      state['updated_at'] = Time.current.iso8601
      state['after_name'] = name unless retrying
      if error
        previous = state.fetch('failures')[id.to_s]
        state['failures'][id.to_s] = {'id' => id, 'name' => name, 'attempts' => previous.to_h.fetch('attempts', 0) + 1,
          'error' => "#{error.class}: #{error.message}".truncate(500)}
      else
        state['failures'].delete(id.to_s)
        state['processed'] += 1
        initial_counters.each_key { |key| state[key] += counters.fetch(key.to_sym, 0) }
      end
      registry.with_lock do
        runs = registry.metadata.to_h.fetch(self.class::STATE_KEY, {}).merge(@run => state)
        registry.update!(metadata: registry.metadata.to_h.merge(self.class::STATE_KEY => runs))
      end
      state
    end

    def emit(**fields)
      @output.puts(fields.merge(registry_id: @registry.id, run: @run, dry_run: @dry_run, at: Time.current.iso8601).to_json)
    end
  end
end
