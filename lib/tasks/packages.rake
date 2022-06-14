namespace :packages do
  desc 'sync recently updated packages'
  task sync_recent: :environment do 
    Registry.sync_all_recently_updated_packages_async
  end

  desc 'sync all packages'
  task sync_all: :environment do
    Registry.sync_all_packages
  end
end