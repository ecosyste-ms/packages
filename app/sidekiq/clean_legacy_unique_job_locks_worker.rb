class CleanLegacyUniqueJobLocksWorker
  include Sidekiq::Worker
  sidekiq_options queue: :low, retry: 3, lock: :until_executing, lock_ttl: 1.hour.to_i

  def perform
    result = LegacyUniqueJobLocks.new(
      apply: true,
      scan_count: LegacyUniqueJobLocks::MAX_SCAN_COUNT
    ).call
    Sidekiq.logger.info("Legacy unique job lock cleanup #{result.except(:sample).to_json}")
    self.class.perform_in(1.minute) unless result[:complete]
  end
end
