namespace :packages do
  desc 'Preview or apply resumable Packagist repairs (DRY_RUN=true, RUN=all, LIMIT=100, MAX_SECONDS=600, PAUSE=1, FROM_ID, TO_ID, NAME, REGISTRY)'
  task cleanup_packagist: :environment do
    dry_run = ENV.fetch('DRY_RUN', 'true')
    raise ArgumentError, 'DRY_RUN must be true or false' unless %w[true false].include?(dry_run)
    registry = Registry.where('lower(ecosystem) = ?', 'packagist')
      .find_by!('lower(name) = ?', ENV.fetch('REGISTRY', 'packagist.org').downcase)
    result = PackagistCleanup.new(registry, run: ENV.fetch('RUN', 'all'), dry_run: dry_run == 'true',
      limit: Integer(ENV.fetch('LIMIT', '100')), max_seconds: Float(ENV.fetch('MAX_SECONDS', '600')),
      pause: Float(ENV.fetch('PAUSE', '1')), from_id: Integer(ENV.fetch('FROM_ID', '0')),
      to_id: ENV['TO_ID'].present? ? Integer(ENV['TO_ID']) : nil, name: ENV['NAME']).run
    abort "Packagist cleanup has #{result.fetch(:failures).size} pending failures; repeat the same command to retry" if !result.fetch(:failures).empty? && dry_run == 'false'
  end
end
