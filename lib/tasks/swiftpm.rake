namespace :packages do
  desc 'normalize Swift GitHub identities in one registry (dry run unless apply=true)'
  task :normalize_swift_names, [:registry_id, :apply] => :environment do |_task, args|
    registry = Registry.find(args.fetch(:registry_id))
    raise ArgumentError, 'Expected a Swift registry' unless registry.ecosystem == 'swiftpm'

    result = registry.ecosystem_instance.normalize_names(dry_run: args[:apply] != 'true')
    puts result.inspect
  end
end
