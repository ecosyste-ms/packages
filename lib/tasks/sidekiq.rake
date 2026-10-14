namespace :sidekiq do
  namespace :unique_jobs do
    desc "List orphaned unique job locks"
    task list: :environment do
      digests = SidekiqUniqueJobs::Digests.new
      entries = digests.entries(pattern: "*", count: 10_000)
      if entries.empty?
        puts "No unique job locks found."
      else
        puts "#{entries.size} unique job lock(s):"
        entries.each do |digest, score|
          time = Time.at(score).utc rescue score
          puts "  #{digest} (scored at #{time})"
        end
      end
    end

    desc "Clear all unique job locks"
    task clear: :environment do
      digests = SidekiqUniqueJobs::Digests.new
      entries = digests.entries(pattern: "*", count: 10_000)
      if entries.empty?
        puts "No unique job locks to clear."
      else
        puts "Clearing #{entries.size} unique job lock(s)..."
        digests.delete_by_pattern("*", count: 10_000)
        puts "Done."
      end

      expiring = SidekiqUniqueJobs::ExpiringDigests.new
      expiring_entries = expiring.entries(pattern: "*", count: 10_000)
      unless expiring_entries.empty?
        puts "Clearing #{expiring_entries.size} expiring digest(s)..."
        expiring.delete_by_pattern("*", count: 10_000)
        puts "Done."
      end
    end

    desc "Clear unique job locks matching a pattern (e.g. PATTERN='*SyncPackage*')"
    task clear_matching: :environment do
      pattern = ENV.fetch("PATTERN") { abort "Usage: rake sidekiq:unique_jobs:clear_matching PATTERN='*SyncPackage*'" }
      digests = SidekiqUniqueJobs::Digests.new
      entries = digests.entries(pattern: pattern, count: 10_000)
      if entries.empty?
        puts "No locks matching '#{pattern}'."
      else
        puts "Clearing #{entries.size} lock(s) matching '#{pattern}'..."
        digests.delete_by_pattern(pattern, count: 10_000)
        puts "Done."
      end
    end

    desc "Report indexed and legacy unindexed unique job locks"
    task audit_locks: :environment do
      puts LegacyUniqueJobLocks.audit.to_json
    end

    desc "Inspect or delete one bounded batch of legacy unindexed locks"
    task clean_legacy_locks: :environment do
      apply = ENV["APPLY"] == "true"
      scan_count = ENV.fetch("COUNT", LegacyUniqueJobLocks::DEFAULT_SCAN_COUNT).to_i
      result = LegacyUniqueJobLocks.new(apply: apply, scan_count: scan_count).call

      puts result.to_json
    end
  end
end
