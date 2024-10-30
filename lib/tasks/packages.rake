namespace :packages do
  desc 'sync recently updated packages'
  task sync_recent: :environment do 
    Registry.sync_all_recently_updated_packages_async
  end

  desc 'sync recently updated npm packages'
  task sync_recent_npm: :environment do
    r = Registry.find_by(ecosystem: 'npm')
    r.sync_recently_updated_packages_async
  end

  desc 'sync_worst_one_percent'
  task sync_worst_one_percent: :environment do
    Registry.sync_worst_one_percent
  end

  desc 'sync all packages'
  task sync_all: :environment do
    Registry.sync_all_packages
  end

  desc 'sync least recently synced packages'
  task sync_least_recent: :environment do
    Package.sync_least_recent_async
  end

  desc 'sync least recently synced top 1% packages'
  task sync_least_recent_top: :environment do
    Package.sync_least_recent_top_async
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

  desc 'update_extra_counts'
  task update_extra_counts: :environment do
    Registry.update_extra_counts
  end

  desc 'sync maintainers'
  task sync_maintainers: :environment do
    Package.sync_maintainers_async
  end

  desc 'update rankings'
  task update_rankings: :environment do
    Package.update_rankings_async
  end

  desc 'update advisories'
  task update_advisories: :environment do
    Package.update_advisories
  end

  desc 'update docker usages'
  task update_docker_usages: :environment do
    Package.update_docker_usages
  end

  desc 'crawl github marketplace'
  task crawl_github_marketplace: :environment do
    registry = Registry.find_by(ecosystem: 'actions')
    repo_names = registry.ecosystem_instance.crawl_marketplace
    registry = Registry.find_by(ecosystem: 'actions')
    repo_names.each do |repo_name|
      registry.sync_package_async(repo_name)
    end
  end

  desc 'crawl recently updated github marketplace'
  task crawl_recently_updated_github_marketplace: :environment do
    registry = Registry.find_by(ecosystem: 'actions')
    repo_names = registry.ecosystem_instance.crawl_recent_marketplace
    repo_names.each do |repo_name|
      registry.sync_package_async(repo_name)
    end
  end

  desc 'sync docker packages'
  task sync_outdated_docker: :environment do
    registry = Registry.find_by(ecosystem: 'docker')
    registry.packages.active.outdated.limit(1000).order('RANDOM()').each do |package|
      puts package.name
      package.sync_async
      sleep 1 # rate limited
    end
  end

  desc 'sync batch registries outdated'
  task sync_batch_registries_outdated: :environment do
    Registry.sync_in_batches_outdated
  end

  desc 'calculate funding domains'
  task calculate_funding_domains: :environment do
    Package.funding_domains
  end

  desc 'update critical packages'
  task update_critical: :environment do
    Registry.all.find_each do |registry|
      registry.find_critical_packages
    end
  end

  desc 'clean up sidekiq unique jobs'
  task clean_up_sidekiq_unique_jobs: :environment do
    REDIS.del('uniquejobs:digests')
  end
end