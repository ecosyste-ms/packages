# frozen_string_literal: true

module PackagistErrorReporting
  class RetriesExhausted < RuntimeError; end

  def report(error, handled:, severity:, context: {}, source: nil)
    if error.is_a?(Dalli::ValueOverMaxSize) && handled && severity == :warning &&
        source == 'mem_cache_store.active_support' && error.message.start_with?('Value for packagist/')
      Rails.logger.warn("Packagist cache write skipped: #{error.message}")
      return
    end

    super
  end

  def self.retries_exhausted(job, error)
    return unless error.is_a?(Ecosystem::Packagist::RetryableError)

    failure = RetriesExhausted.new("#{job['class']} exhausted retries: #{error.message}")
    failure.set_backtrace(error.backtrace)
    Appsignal.report_error(failure) do |transaction|
      transaction.set_action("#{job['class']}#perform")
      transaction.set_namespace('background')
      transaction.add_tags(job_id: job['jid'], retry_count: job['retry_count'])
      transaction.add_function_parameters { job['args'] }
    end
  end
end
