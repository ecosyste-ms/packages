namespace :packages do
  task sync_recent: :environment do 
    Registry.sync_all_recently_updated_packages_async
  end
end