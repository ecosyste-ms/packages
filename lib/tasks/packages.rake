namespace :packages do
  desc 'sync recently updated packages'
  task sync_recent: :environment do 
    Registry.sync_all_recently_updated_packages_async
  end

  desc 'sync all packages'
  task sync_all: :environment do
    Registry.sync_all_packages
  end

  desc 'sync least recently synced packages'
  task sync_least_recent: :environment do
    Package.sync_least_recent_async
  end

  desc 'check package statuses'
  task check_statuses: :environment do
    Package.check_statuses_async
  end

  desc "sync missing packages"
  task sync_missing: :environment do
    Registry.sync_all_missing_packages_async
  end

  desc 'update repo metadata'
  task update_repo_metadata: :environment do
    Package.update_repo_metadata_async
  end

  desc "parse unique maven names"
  task parse_maven_names: :environment do
    names = Set.new

    File.readlines('terms.txt').each_with_index do |line,i|
      parts = line.split('|')
      names.add [[parts[0], parts[1]].join(':')]
      puts "#{i} row (#{names.length} uniq names)" if i % 10000 == 0
    end
  
    puts names.length
    File.write('unique-terms.txt', names.to_a.join("\n"))
  end

  desc 'sync package download counts'
  task sync_download_counts: :environment do
    Package.sync_download_counts_async
  end

  desc 'update_funded_packages_count'
  task update_funded_packages_count: :environment do
    Registry.update_funded_packages_count
  end
end